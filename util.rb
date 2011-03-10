require 'fileutils'
require 'net/http'
require 'net/https'
require 'digest/sha1'
require 'erb'

STARTDIR = Dir.getwd()

# --------------------------------------------------

OPTS  = {}
CACHE = {}

# --------------------------------------------------

def os_arch
  x = CACHE[:os_arch] || (os() + "." + `uname -m`.chomp)
  CACHE[:os_arch] = x
  x
end

def os
  x = CACHE[:os] || `uname -s`.chomp
  CACHE[:os] = x
  x
end

def os_nbits
  # Note that we might be running a 32-bit OS on a 64-bit processor.
  # Here we want to number of OS bits.

  case os_short()
    when 'win'
      # The pa looks like "AMD64" on a 64-bit box.
      pa = ENV["PROCESSOR_ARCHITEW6432"] || ""
      wd = ENV["WINDIR"] || "/Windows"
      # One day, the directory check will break when MSFT
      # removes 32-bit backwards compatibility.
      if pa.match(/64/) and File.directory?(wd + "/SysWOW64")
        '64'
      else
        '32'
      end
    when 'sunos'
      `isainfo -b`.chomp()
    when 'linux'
      if `uname -m`.chomp() == "x86_64"
        '64'
      else
        '32'
      end
    when 'darwin'
      print "WARNING: Reporting this as a 32 bit platform..\n"
      '32'
    else
      print "ERROR: Don't know to detect the number of bits on this platform.\n"
      exit(1)
  end
end

def os_short
  x = os().downcase
  x.gsub(/[0-9\.]/, '').
    gsub(/mswin*/i, 'win').
    gsub(/mingw*/i, 'win').
    gsub(/_nt-/i, '')
end

def arch
  `uname -m`.chomp.gsub(/i686/, "x86").gsub(/i386/, "x86")
end

def is_rhel?
  File.exists?("/etc/redhat-release")
end

def is_ubuntu?
  File.exists?("/etc/lsb-release") || File.exists?('/etc/debian_version')
end

def os_general
  if is_windows?
    'win'
  else
    'nix'
  end
end

def is_windows?
  os_short() == 'win'
end

def path_delimiter
  if is_windows?
    ';'
  else
    ':'
  end
end

def product_platform() # Might be overridden by platform specific Manifest_XXX.rb
  os_arch
end

# --------------------------------------------------

$collected = []

PROGRAM_FILES = '/Program Files'

INSTALL_SHIELDS = [
  "/Program Files/InstallShield/2010\ StandaloneBuild/System/IsCmdBld.exe",
  "/Program Files (x86)/InstallShield/2010\ StandaloneBuild/System/IsCmdBld.exe",
  "/Program Files/InstallShield/2010/System/IsCmdBld.exe",
  "/Program Files (x86)/InstallShield/2010/System/IsCmdBld.exe"
]

INSTALL_SHIELD = INSTALL_SHIELDS.find {|x| File.exists?(x)}

DOTNET_FRAMEWORK_4 = '/c/Windows/Microsoft.NET/Framework/v4.0.30319'

def builder_base()
  if is_windows?
    PROGRAM_FILES
  else
    # TODO: Linux / OSX version, too.
    '/usr/local/lib'
  end
end

BIN_PATH = ["/mingw/bin",
            "/msys/1.0/bin",
            "#{PROGRAM_FILES}/git/bin",
            "/sw/bin",
            "/bin",
            "/msysgit/msysgit/bin",
            "/c/msysgit/msysgit/bin"].
           concat((ENV['PATH'] || "").
                  split(path_delimiter())).
           map {|x| x + '/'}

# --------------------------------------------------
def builder_erlang_base()
  if is_windows?
    '/c'
  else
    '/usr/local/lib'
  end
end

def builder_erlang_dir()
  if is_windows?
    'erl' + ERLANG_VER
  else
    'erlang'
  end
end

# --------------------------------------------------

def get_package_prefix(dc_name)
  rv = "#{COMPANY}-#{dc_name}" # Ex: "membase-server", "membase-devkit".
  rv = "moxi-server" if dc_name == "moxi"
  rv
end

# Builds a product's installer.
#
def build_product(name, final_package_prefix=nil)
  dc_name = name.downcase # Ex: 'server', 'devkit', 'moxi'

  act_name = dc_name
  act_name = 'membase' if dc_name == 'server'

  package_prefix = get_package_prefix(dc_name)

  case os_short()
    when 'win'
      fix_ism("is_#{dc_name}/#{dc_name}.ism")
      fix_script("is_#{dc_name}/Script Files/Setup.Rul", dc_name)
      sh "\"#{INSTALL_SHIELD}\" -p is_#{dc_name}/#{dc_name}.ism"
      package_prefix = final_package_prefix if final_package_prefix
      FileUtils.cp(Dir.glob("./is_#{dc_name}/PROJECT*/**/setup.exe")[0],
                   "./is_#{dc_name}/#{package_prefix}_setup.exe")
    else
      # For other generic unix-y platforms, do a tar'ing.
      # Here, we depend on a previous build_product_mm() step to
      # have filled the out directory with the right files.
      out_dir = get_tmp("#{package_prefix}", false)

      if latest_only()
        suffix = 'latest'
      else
        suffix = product_version()
      end

      if "#{dc_name}" != "devkit"
        if is_rhel?
          # PRODUCT_VERSION looks like 0.0.0-0-g12344321-linux.i686
          # Let's put the git id as the release
          #
          familiarize = "./RedHat/familiarize_#{act_name}.sh RedHat" +
            " #{File.dirname(out_dir)}/#{File.basename(out_dir)} #{PRODUCT_VERSION_PREFIX} 1"
          hard_sh(familiarize)
        elsif is_ubuntu?
          # PRODUCT_VERSION looks like 0.0.0-0-g12344321-linux.i686
          # Let's put the git id as the release
          #
          make_bin_dist = "./Ubuntu/make_bin_dist_#{act_name}.sh Ubuntu" +
            " #{File.dirname(out_dir)}/#{File.basename(out_dir)} #{PRODUCT_VERSION_PREFIX} 1"
          hard_sh(make_bin_dist)
        end
      end

      if os_short() == 'sunos'
        tar = "gtar"
      else
        tar = "#{bin('tar')}"
      end

      print "File.dirname(out_dir): #{File.dirname(out_dir)}\n"

      package = "#{package_prefix}_#{suffix}.tar.gz"
      cmd = "#{tar} --directory #{File.dirname(out_dir)}" +
             " -czf #{package}" +
             " #{File.basename(out_dir)}"
      hard_sh(cmd)

      if "#{dc_name}" != "devkit"
        if is_rhel?
          package = "./#{package_prefix}_#{arch}_#{PRODUCT_GIT_DESCRIBE}.rpm"
          cmd = "rm -f #{package_prefix}_#{arch}_*.rpm"
          hard_sh(cmd)

          cmd = "cp #{package_prefix}_#{suffix}.tar.gz" +
            " ~/rpmbuild/SOURCES/#{package_prefix}_#{PRODUCT_VERSION_PREFIX}.tar.gz"
          hard_sh(cmd)
          cmd = "rpmbuild -bb RedHat/#{package_prefix}.spec.#{PRODUCT_VERSION_PREFIX}"
          hard_sh(cmd)
          cmd = "rm RedHat/#{package_prefix}.spec.#{PRODUCT_VERSION_PREFIX}"
          hard_sh(cmd)

          cmd = "mv ~/rpmbuild/RPMS/*/#{package_prefix}-#{PRODUCT_VERSION_PREFIX}-1.*.rpm #{package}"
          hard_sh(cmd)
        elsif is_ubuntu?
          package = "./#{package_prefix}_#{arch}_#{PRODUCT_GIT_DESCRIBE}.deb"
          cmd = "rm -f #{package_prefix}_#{arch}_*.deb"
          hard_sh(cmd)

          cmd = "mv ./Ubuntu/deb-dev/#{package_prefix}_*.deb #{package}"
          hard_sh(cmd)
        end
      end

      if package
        if final_package_prefix
          package_prev = package
          package = final_package_prefix + '_' + package.split('_')[1..-1].join('_')
          cmd = "mv #{package_prev} #{package}"
          hard_sh(cmd)
        end

        hard_sh("md5sum #{package} > #{package}.md5")
      end
  end
end

# Builds a merge module, which is a dependency on the pathway to an installer.
#
def build_product_mm(name, name_final)
  dc_name       = name.downcase
  dc_name_final = name_final.downcase

  case os_short()
    when 'win'
      fix_ism("is_#{dc_name}_mm/#{dc_name}_mm.ism")
      sh "\"#{INSTALL_SHIELD}\" -p is_#{dc_name}_mm/#{dc_name}_mm.ism"
    else
      # For other platforms, just prepare files for a later tar'ing.
      #
      package_prefix = get_package_prefix(dc_name_final)

      out_dir = get_tmp("#{package_prefix}", false)
      print "merging files from #{name} into #{out_dir}\n"
      c = Dir.glob("./components/#{name}/*")
      if c.length > 0
        c.each do |x|
          print("merging file #{x}\n")
          FileUtils.cp_r(x, out_dir)
        end
      else
        print "ERROR: expected to merge 1 or more files, but only got: #{c}\n"
        exit(1)
      end
  end
end

def fix_script(path, dc_name)
  if is_windows?
    s_before = File.new(path, 'r').read
    s_after  = s_before

    if os_nbits() == '32'
      # For bug 583...
      print "INFO: fixing script to have right OS_NBITS\n"
      src = "#define BUILD_OS_NBITS 64"
      dst = "#define BUILD_OS_NBITS 32"
      print "INFO: final OS_NBITS line: #{dst}\n"
      s_after = s_after.gsub(src) {|match| dst}
    end

    # For bug 154...
    print "INFO: fixing script to have right BUILD_PRODUCT_NAME_SHORT\n"
    src = "#define BUILD_PRODUCT_NAME_SHORT \"devkit\""
    dst = "#define BUILD_PRODUCT_NAME_SHORT \"#{dc_name}\""
    print "INFO: final BUILD_PRODUCT_NAME_SHORT line: #{dst}\n"
    s_after = s_after.gsub(src) {|match| dst}

    if s_before != s_after
      print "INFO: fixing scripts, in file #{path}\n"
      File.open(path, 'w') {|fw| fw.write(s_after)}
    else
      print "INFO: skipping fixing script, no change to #{path}\n"
    end
  end
end

def fix_ism(path)
  if is_windows?
    content_before = File.new(path, 'r').read
    content_after  = content_before

    # PRODUCT_VERSION looks like 0.0.0-0-g12344321-win32
    # or, like 1.0.2rc1-win32
    #
    v_parts = PRODUCT_VERSION.split('-')[0].split('.')

    ver_ism = "#{v_parts[0]}.#{v_parts[1]}.#{v_parts[2]}"
    if ver_ism.match(/^[0-9]+\.[0-9]+\.[0-9a-z]+$/)
      print "INFO: fixing ism ProductVersion to #{ver_ism}\n"
      content_after = content_after.gsub(/<td>ProductVersion<\/td><td>(.*?)<\/td>/,
                                         "<td>ProductVersion</td><td>#{ver_ism}</td>")
    else
      print "ERROR: improper version: #{PRODUCT_VERSION} gave #{ver_ism}\n"
      exit(1)
    end

    cpath = File.expand_path('./components')
    cpath = cpath.gsub(/\//, "\\")
    if cpath.downcase != "C:\\dev\\wallace\\components".downcase
      print "INFO: fixing ism paths to #{cpath}\n"
      src = "<td>PATH_TO_COMPONENTS_FILES<\/td><td>C:\\dev\\wallace\\components<\/td>"
      dst = "<td>PATH_TO_COMPONENTS_FILES<\/td><td>#{cpath}<\/td>"
      print "INFO: final line: #{dst}\n"

      # Have to use block form of gsub, because there might be "\1"
      # characters on in the path on the builder, which could be
      # incorrectly interpreted as substitutions with the usual
      # string-based gsub.
      #
      content_after = content_after.gsub(src) {|match| dst}
    else
      print "INFO: skipping ism cpath fix, no change to #{cpath}\n"
    end

    if os_nbits() == '64'
      # For bug 622, disallowing 64-bit setup.exe from running on 32-bit windows.
      print "INFO: fixing ism bitsize to x64\n"
      # The 1033 stands for English.
      src = "<template>Intel;1033<\/template>"
      dst = "<template>x64;1033<\/template>"
      print "INFO: final template line: #{dst}\n"
      content_after = content_after.gsub(src) {|match| dst}
    end

    if content_before != content_after
      print "INFO: fixing ism, in file #{path}\n"
      File.open(path, 'w') {|fw| fw.write(content_after)}
    else
      print "INFO: skipping fixing ism, no change to #{path}\n"
    end
  end
end

# --------------------------------------------------

def find_trees()
  trees = {}

  PRODUCT_NAMES.each do |x|
    tree = {}
    dir_tree_paths("./components/#{x}").sort.each do |path|
      dir = File.dirname(path)
      tree[dir] ||= []
      tree[dir] << path
    end
    trees[x.downcase] = tree
  end

  trees
end

# --------------------------------------------------

# InstallShield wants a UUID that looks like...
#
#   aa48f546c7dbf95b7517b412f995b487
#
def uuid(s, path=nil)
  size = 0
  if path
   size = File.size(path)
   s = s + ':' + size.to_s if size > 0
  end
  Digest::SHA1.hexdigest(s)[0, 32]
end

def dir_tree_paths(dir_path)
  paths = []
  dir_tree_visit(dir_path) {|p| paths << p}
  paths
end

def dir_tree_visit(dir_path, &block)
  Dir.new(dir_path).each do |file|
    next if file.match(/^\.+/)
    child_path = "#{dir_path}/#{file}"
    if FileTest.directory?(child_path)
      dir_tree_visit(child_path, &block)
    else
      yield child_path
    end
  end
end

# --------------------------------------------------

def bin(prog)
  p = BIN_PATH.find {|b| (File.directory?(b)) and
                         (File.exists?(b + "/#{prog}") or
                          File.exists?(b + "/#{prog}.exe"))}
  (p || '') + prog
end

def unzip(path_zip, dest_dir=nil)
  dest_dir = File.dirname(path_zip) unless dest_dir
  sh "#{bin('unzip')} -u #{path_zip} -d #{dest_dir}"
end

def unzip_proc(suffix = "")
  (Proc.new do |what, path|
     unzip(path, File.dirname(path) + suffix)
   end)
end

def mv_dir_proc()
  (Proc.new do |what, files|
    if files.length == 1
      dst_dir = what[:dst_dir]
      FileUtils.mkdir_p(dst_dir)
      FileUtils.rm_rf(dst_dir)
      print "INFO: mv_dir_proc, moving #{files[0]} to #{dst_dir}\n"
      FileUtils.mv("#{files[0]}", dst_dir)
    else
      unless skip_make()
        print "ERROR: expected just 1 dir; got #{files}\n"
        exit
      end
    end
   end)
end

def tarx_dir_proc()
  # Just extract this tarball into place for the product
  (Proc.new do |what, files|
    dst_dir = what[:dst_dir]
    basename = files # it's not really files, so ...
    if os != "Linux"
      print "ERROR: tarx_dir_proc isn't portable but called on #{os} rather than Linux\n"
      exit(1)
    end
    tarfile = "components/tmp/src_" + basename + ".tar.gz/" +
              basename + "/" + basename + "-" + os + "." + (`uname -m`.chomp) + ".tar.gz"
    print "INFO: tarx_dir_proc is to untar #{tarfile} to #{dst_dir}\n"
    print "current working dir is " + `pwd`
    untgzp(tarfile, dst_dir)
    # components/tmp/src_google-perftools-1.6.tar.gz/google-perftools-1.6/google-perftools_1.6-Linux.x86_64.tar.gz
  end)
end

def mv_files_proc(mapping)
  mv_files_proc_ex(mapping, true, false)
end

def mv_files_proc_ex(mapping, use_mv_sub_files, clean_before_mv)
  mapping ||= []
  # The mapping should be a [[regexp, dst_dir]*], or
  # an array of [regexp, dst_dir] pairs.
  (Proc.new do |what, files|
     files.each do |file|
       basename = File.basename(file)
       pattern_dst_dir = mapping.find {|pattern_dst_dir| basename.match(pattern_dst_dir[0])}
       dst_dir = what[:dst_dir]
       dst_dir = pattern_dst_dir[1] if pattern_dst_dir
       FileUtils.mkdir_p(dst_dir)
       if File.exists?(dst_dir + '/' + basename) and File.directory?(file) and use_mv_sub_files
         mv_sub_files(file, dst_dir)
       else
         print "INFO: mv_files_proc_ex, moving #{file} to #{dst_dir}\n"
         FileUtils.rm_rf(dst_dir + '/' + basename) if clean_before_mv
         FileUtils.mv(file, dst_dir + '/')
       end
     end
   end)
end

def mv_sub_files_proc(safe=false)
  # Expecting files to be a like ["src_dir"], and we move
  # all the files in src_dir/* to dst_dir.
  (Proc.new do |what, fs|
     if fs.length == 1
       src_dir = fs[0]
       dst_dir = what[:dst_dir]
       if safe
         mv_sub_files_safe(src_dir, dst_dir)
       else
         mv_sub_files(src_dir, dst_dir)
       end
     else
       unless skip_make()
         print "ERROR: expected just 1 src_dir; got #{fs}.\n"
         exit(1)
       end
     end
   end)
end

def mv_sub_files(src_dir, dst_dir)
  # Unlike a FileUtils.mv(src_dir, dst_dir), this
  # function won't complain if dst_dir already exists.
  FileUtils.mkdir_p(dst_dir)
  Dir.glob(src_dir + "/*").each {|f|
    x = dst_dir + "/" + File.basename(f)
    print "INFO: mv_sub_files: #{f} to #{x}\n"
    FileUtils.rm_rf(x)
    FileUtils.mv(f, x)
  }
  FileUtils.rm_rf(src_dir) # This simulates a mv.
end

def mv_sub_files_safe(src_dir, dst_dir)
  # Recursive version of mv_sub_files that doesn't overwrite
  # existing sibling files in dst.
  FileUtils.mkdir_p(dst_dir)
  Dir.glob(src_dir + "/*").each {|f|
    x = dst_dir + "/" + File.basename(f)
    print "INFO: mv_sub_files: #{f} to #{x}\n"
    if File.directory?(f) and File.directory?(x)
      mv_sub_files(f, x)
    else
      FileUtils.rm_rf(x)
      FileUtils.mv(f, x)
    end
  }
  FileUtils.rm_rf(src_dir) # This simulates a mv.
end

def untgz(path)
  if path[-7..-1] != ".tar.gz"
    print "ERROR: expected a tar.gz path: #{path}\n"
    exit
  end
  # Example: path is /foo/bar.tar.gz
  path_dirname = File.dirname(path)              # /foo
  path_basename = File.basename(path)            # bar.tar.gz
  path_basename_tar = File.basename(path, '.gz') # bar.tar
  sh "#{bin('gzip')} -f -d #{path}"
  if os_short() == 'sunos'
     tar = "gtar"
  else
     tar = "#{bin('tar')}"
  end

  sh "#{tar} --directory #{path_dirname} -xf #{path_dirname}/#{path_basename_tar}"
  FileUtils.rm_rf("#{path_dirname}/#{path_basename_tar}")
end

# untar the file in the location
def untgzp(file, location)
  if file[-7..-1] != ".tar.gz"
    print "ERROR: expected a tar.gz file: #{file}\n"
    exit
  end
  if os_short() == 'sunos'
     tar = "gtar"
  else
     tar = "#{bin('tar')}"
  end
  sh "#{tar} --directory #{location} -xf #{file}"
end

# --------------------------------------------------

def src_make(base, src_tgz, extra = {})
  Proc.new {|what|
    print "INFO: src_make of #{src_tgz} from #{base}\n"
    base_src_tgz = "#{base}/#{src_tgz}"

    if File.exists?(base_src_tgz)
      skip_test = extra[:test]
      skip_test = skip_test.gsub(/^\/c\//, "c:\/") if skip_test.class == String

      if (not skip_test) or (not File.exists?(skip_test.to_s))
        tmp = get_tmp("src_" + src_tgz)
        FileUtils.cp(base_src_tgz, tmp)

        before = Dir.entries(tmp)
        untgz(tmp + '/' + src_tgz)
        after = Dir.entries(tmp)

        src = (after - before)[0]

        cwd = Dir.getwd()
        begin
          Dir.chdir("#{tmp}/#{src}")
          print "INFO: cwd is #{Dir.getwd()}\n"
          if extra[:make] and not skip_make(extra)
            extra[:make].map do |cmd|
              hard_sh(cmd)
            end
          end
        ensure
          Dir.chdir(cwd)
        end
      else
        print "INFO: skipping src_make of #{src_tgz} since existence test passes\n"
      end
      $collected += [src_tgz]
    else
      print "WARNING: trying to src_make missing: #{src_tgz}\n"
    end
  }
end

def latest_only(extra = {})
  OPTS[:latest] or extra[:latest]
end

def local_only(extra = {})
  OPTS[:local] or extra[:local]
end

def skip_make(extra = {})
  OPTS[:skip_make] or extra[:skip_make]
end

# --------------------------------------------------

def pull_make(base, name, tag_ver, kind, extra = {})
  Proc.new {|what|
    latest = latest_only(extra)
    local  = local_only(extra)

    os_arch_str = ""
    os_arch_str = "-" + os_arch if extra[:os_arch]
    want = "#{name}_#{tag_ver}#{os_arch_str}.#{kind}"
    FileUtils.mkdir_p(base)

    skip_test = extra[:test]
    skip_test = skip_test.gsub(/^\/c\//, "c:\/") if skip_test.class == String

    base_want = "#{base}/#{want}"
    if (skip_test and File.exists?(skip_test.to_s)) or
       ((not latest) and File.exists?(base_want))
      print "INFO: skipping pull of existing #{want}\n"
    else
      cwd = Dir.getwd()
      begin
        repo = extra[:repo] || name

        print "INFO: pulling #{repo}\n"

        tmp_repo = get_repo(repo)

        # If we're getting the latest, try to reuse a previous
        # git clone if available.
        #
        if (not latest) or
           (not File.directory?(tmp_repo)) or
           (not File.directory?(tmp_repo + "/.git"))
          print "INFO: git clone of #{tmp_repo}\n"

          if (not local)
            FileUtils.rm_rf(tmp_repo)
            begin
              raise if OPTS[:github_only]
              hard_sh("git clone #{GITPRIV}/#{repo}.git #{tmp_repo}")
            rescue
              hard_sh("git clone #{GITHUB}/#{repo}.git #{tmp_repo}")
            end
          else
            if (File.directory?(tmp_repo))
              print "ERROR: really need the internet. local_only build not possible.\n"
              exit(1)
            else
              print "INFO: using local, pre-existing #{tmp_repo}\n"
            end
          end
        else
          print "INFO: reusing previous git clone of #{tmp_repo}\n"
        end

        Dir.chdir(tmp_repo)

        if (not local)
          hard_sh("git remote update")
          hard_sh("git fetch --tags")

          if extra[:branch]
            hard_sh("git checkout -f #{extra[:branch]}")
            hard_sh("git pull #{extra[:branch].gsub(/\//, ' ')}")
          else
            hard_sh("git pull origin master")
          end
        else
          print "INFO: skipping git fetch/checkout/pull due to local_only for #{tmp_repo}\n"
        end

        if latest
          print "INFO: using latest version of #{repo}\n"

          v = git_describe()
          v = v.gsub(/-/, "_")
          w = "#{name}_#{v}#{os_arch_str}.#{kind}"
          base_want = "#{base}/#{w}"
        else
          print "INFO: using #{tag_ver} version of #{repo}\n"
          checkout_arg = parse_tag_ver(tag_ver)
          hard_sh("git checkout #{checkout_arg}")
        end

        Dir.chdir(cwd)

        if File.exists?(base_want)
          print "INFO: skipping remake because #{base_want} already exists\n"
        else
          print "INFO: making #{name} in #{tmp_repo} to get #{base_want}\n"

          Dir.chdir(tmp_repo)

          if (not local)
            hard_sh("git submodule init")
            hard_sh("git submodule update")
          else
            print "INFO: skipping git submodule'ing due to local_only for #{tmp_repo}\n"
          end

          if extra[:premake] and not skip_make(extra)
            extra[:premake].map do |cmd|
              if cmd.class == Proc
                cmd.call(what)
              else
                hard_sh(cmd)
              end
            end
          end

          before = after = []

          unless skip_make(extra)
            if extra[:make]
              extra[:make].map do |cmd|
                hard_sh(cmd)
              end
            else
              hard_sh("make")
              before = Dir.glob("#{name}_*.#{kind}")
              hard_sh("make bdist")
              after = Dir.glob("#{name}_*.#{kind}")
            end
          end

          Dir.chdir(cwd)

          if !(extra[:skip_file]) and not skip_make(extra)
            if latest
              want = (after - before)[0]
                unless want
                  want = Dir.glob("#{tmp_repo}/#{name}_*#{os_arch_str}.#{kind}")[0]
                end
                want = File.basename(want)
                base_want = "#{base}/#{want}"
                print "INFO: latest is #{base_want}\n"
            end

            FileUtils.cp("#{tmp_repo}/#{want}", base_want)
          end

          if latest and extra[:skip_file] and (skip_test == :stamp)
            hard_sh("touch #{base_want}")
          end
        end
      ensure
        Dir.chdir(cwd)
      end
    end

    $collected += [base_want]
    base_want
  }
end

def git_describe()
  `#{bin('git')} describe`.chomp
end

# Ex: a tag_ver looks like "1.0.0", "1.0.2rc1" or "1.0.0_43_g34fdfaf".
#
def parse_tag_ver(tag_ver)
  parts = tag_ver.split('_')
  if parts[2]
    parts[2][1..-1] # Strip off 'g' prefix.
  else
    parts[0]
  end
end

# --------------------------------------------------

START_DIR = Dir.getwd()

def get_repo(repo)
    if repo && repo.match(/^\./)
        return START_DIR + "/" + repo
    end
    START_DIR + "/../#{repo}"
end

def get_tmp_path(suffix = "")
    './components/tmp/' + suffix
end

def get_tmp(suffix = "", clean = true)
    tmp = get_tmp_path(suffix)
    if clean
      FileUtils.rm_rf(tmp)
    end
    FileUtils.mkdir_p(tmp)
    tmp
end

# ---------------------------------------------

def collect_src_url(src_url, dst_dir, size, src_alt)
  print "INFO: collect_src_url #{src_url}\n"
  name = File.basename(src_url)
  FileUtils.mkdir_p(dst_dir)
  path = dst_dir + '/' + name
  if File.exist?(path) and File.size(path) == size
    print "collect: file #{path} exists\n"
  else
    data = nil
    if src_alt
      src_alt_path = src_alt + '/' + name
      if File.exists?(src_alt_path)
        data = File.open(src_alt_path, 'r') {|f| f.read}
      end
    end
    unless data
      url = URI.parse(src_url)
      begin
        data = Net::HTTP.get(url)
      end
    end
    raise("could not download #{src_url}") unless data
    unless data.size == size
      raise("download #{src_url} had size #{data.size} " +
            "instead of expected #{size}")
    end
    File.open(path, 'wb') {|f| f.write(data)}
    unless File.size(path) == size
      raise "file size wrong #{size} for #{path}"
    end
  end
  path
end

def collect_src_dir(src_dir, dst_dir, except, force = false)
  if (force or (not File.directory?(dst_dir))) or Dir.entries(dst_dir).length <= 3
    f = Dir.glob(src_dir + '/**/*')
    except = except || []
    except.each {|pattern| f = f - f.grep(pattern)}
    if f.length <= 0
      print "WARNING: trying to collect empty: #{src_dir}\n"
    end
    f.each do |path|
      sub_path = path[src_dir.length .. -1]
      if File.directory?(path)
        FileUtils.mkdir_p(dst_dir + '/' + sub_path)
      else
        p "collecting #{path}"
        FileUtils.cp(path, dst_dir + '/' + sub_path)
      end
    end
  else
    print "INFO: skipping already collected: #{dst_dir}\n"
  end
  dst_dir
end

def collect_src_file(src_file, dst_dir, src_alt, dst_base = nil)
  src_path = src_file
  src_base = File.basename(src_path)
  dst_base ||= src_base

  if not File.exists?(src_path) and src_alt
    src_path = src_alt + "/" + src_base
    print "INFO: collect_src_file trying alternate source #{src_path} instead of #{src_file}\n"
  end

  if File.exists?(src_path)
    print "INFO: collect_src_file collecting #{src_path} into #{dst_dir}\n"
    if !File.exists?(dst_dir)
      FileUtils.mkdir_p(dst_dir)
    end
    FileUtils.cp(src_path, dst_dir + '/' + dst_base)
  else
    print "ERROR: collect_src_file could not find #{src_path} or #{src_file}\n"
    exit(1)
  end

  dst_dir + '/' + src_base
end

def collect_src_tgz(src_tgz)
  src_basename_tgz = File.basename(src_tgz)
  if File.exists?(src_tgz)
    print "INFO: collecting src_tgz: #{src_tgz}\n"
    tmp = get_tmp("collect_#{src_basename_tgz}", false)
    FileUtils.cp(src_tgz, tmp)
    before = Dir.entries(tmp)
    untgz(tmp + '/' + src_basename_tgz)
    after = Dir.entries(tmp)
    diff = after - before
    files = diff.map {|x| "#{tmp}/#{x}"}
    return files
  else
    unless skip_make()
      print "ERROR: trying to collect missing src_tgz: #{src_tgz}\n"
      exit(1)
    end
  end
  []
end

def collect_src_lib(src_lib)
  print "INFO: collect_src_lib with #{src_lib}\n"
  # nothing to do here yet, as the step builds a tarball
  return src_lib
end

def collect_src_zip(src_zip)
  src_basename_zip = File.basename(src_zip)
  if File.exists?(src_zip)
    tmp = get_tmp_path("collect_#{src_basename_zip}")
    ent = []
    ent = (Dir.entries(tmp) - [".", ".."]) if File.directory?(tmp)
    if ent.length > 0
      print "INFO: skipping already collected src_zip: #{src_zip}\n"
      files = ent.map {|x| "#{tmp}/#{File.basename(x)}"}
      return files
    else
      print "INFO: collecting src_zip: #{src_zip}\n"
      tmp = get_tmp("collect_#{src_basename_zip}")
      before = Dir.entries(tmp)
      FileUtils.cp(src_zip, tmp)
      unzip(tmp + '/' + src_basename_zip)
      FileUtils.rm_f(tmp + '/' + src_basename_zip)
      after = Dir.entries(tmp)
      diff = after - before
      files = diff.map {|x| "#{tmp}/#{File.basename(x)}"}
      return files
    end
  else
    print "ERROR: trying to collect missing src_zip: #{src_zip}\n"
    exit(1)
  end
  []
end

# ---------------------------------------------

def product_version
  if latest_only()
    PRODUCT_VERSION + "-" + Time.now.strftime("%Y%m%d%H%M")
  else
    PRODUCT_VERSION
  end
end

# --------------------------------------------------

def hard_sh(cmd)
  sh cmd do |ok, res|
    if not ok
      e = "ERROR: cmd failed: #{cmd}\nERROR: with result: #{ok}, #{res}\n"
      raise e
    end
  end
end

# --------------------------------------------------

def component_tag(name,
                  manifest_path = "./components/Server/manifest.txt")
  begin
    manifest = File.open(manifest_path) {|f| f.readlines }
  rescue
    return nil
  end

  line = manifest.select {|line| line.match("^#{name}_")}.first
  if line
    version_suffix_tgz = line.chomp()[(name.length + 1)..-1]
    # version_suffix_tgz looks like...
    #   1.6.0-Darwin.i386.tar.gz
    #   1.4.4_304_g7d5a132-Darwin.i386.tar.gz
    #   1.6.1rc1.tar.gz
    #   1.6.2-10-g2887a43-Darwin.i386

    version_suffix = version_suffix_tgz
    if version_suffix.match(".tar.gz$")
      version_suffix = version_suffix_tgz[0..-8]
    end
    # version_suffix looks like...
    #   1.6.0-Darwin.i386
    #   1.4.4_304_g7d5a132-Darwin.i386
    #   1.6.1rc1
    #   1.6.2-10-g2887a43-Darwin.i386

    version = version_suffix.split('-')[0]
    if version_suffix.split('-').length > 2
      version = version_suffix.split('-')[0..-2].join('_')
    end
    # version looks like...
    #   1.6.0
    #   1.4.4_304_g7d5a132
    #   1.6.1rc1

    tag = version
    tag_split = tag.split('_')
    if tag_split.length > 2
      tag = tag_split[2][1..-1]
    elsif tag_split.length > 1
      tag = tag_split[0]
    end
    # tag looks like '1.6.0', '7d5a132', or '1.6.1rc1'

    return tag
  end

  return nil
end


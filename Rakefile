# Please see DEVNOTES.txt to learn about the prerequisites for this Rakefile.
#
# Running 'rake' will build productized installers.
#
# On windows, for example, it will emit setup.exe installers.
#
require 'fileutils'
require 'net/http'
require 'net/https'
require 'digest/sha1'
require 'erb'
require 'pathname'

COMPANY = 'couchbase'

load('util.rb')

# --------------------------------------------------

if File.exists?("./Manifest_local.rb")
  print("info: manifest: ./Manifest_local.rb\n")
  load("./Manifest_local.rb")
else
  print("info: manifest: ./Manifest.rb\n")
  load("./Manifest.rb")
end

# --------------------------------------------------

i = 1

COLLECT = ((COLLECT_INDEPENDENT.clone().concat(COLLECT_PLATFORM)).map do |x|
              x[:seq] ||= i
              i = i + 1
              x
            end).sort {|x, y| x[:seq] <=> y[:seq]}

# --------------------------------------------------

desc "build product using explicit Manifest versions"
task :default => [:clean, :build, :report]

desc "use HEAD in component repositories, ignoring explicit Manifest versions"
task :latest => [:latest_only, :build, :report]

task :report do
  Dir.glob('**/*setup*.exe').each {|x| p x}
end

task :pre_build => [:collect, :post_collect, :gen_all]
task :build     => [:pre_build, :build_server]

# ---------------------------------------------

desc "github clone/pull on components, useful for development"
task :pull => [:latest_only, :skip_make, :collect, :commit_hook]

# ---------------------------------------------

desc "show the component collection steps that wallace would take"
task :show_component_steps do
  COLLECT.each {|x| print("#{x[:seq]} - #{x[:desc]}\n")}
end

# ---------------------------------------------

# These targets support the 'make dist'.
#
desc "collect component source files"
task :collect_source => [:skip_make, :pre_build] do
  cwd = Dir.getwd()

  COLLECT.each do |x|
    if x[:dist] != false and x[:dist].class != String
      name = x[:desc]

      dist_repo = get_repo(x[:dist_repo] || name)

      print "INFO: -----------------------------------\n"
      print "INFO: collect_source: #{name} at #{dist_repo}\n"

      Dir.chdir(cwd)
      Dir.chdir(dist_repo)

      if File.exists?("./config/version.pl") &&
         File.exists?("./m4")
        hard_sh("perl ./config/version.pl")
      end
    end
  end

  Dir.chdir(cwd)
end

desc "collect component make dist outputs"
task :collect_source_make_dist => [:build, :components_make_dist, :components_make_dist_untgz]

# TODO: These are listed in SKIP_MAKE_DIST until their 'make dist' is fixed.
#
SKIP_MAKE_DIST = []

task :components_make_dist do
  cwd = Dir.getwd()

  FileUtils.rm_rf("./components/tmp/make_dist")
  FileUtils.mkdir_p("./components/tmp/make_dist")

  COLLECT.each do |x|
    if x[:dist] != false and x[:dist].class != String
      n = x[:desc]

      dist_repo = get_repo(x[:dist_repo] || n)

      print "INFO: -----------------------------------\n"
      print "INFO: components_make_dist: #{n} at #{dist_repo}\n"

      Dir.chdir("./components/tmp/#{dist_repo}")

      unless SKIP_MAKE_DIST.include?(n)
        # Remove any previous tar.gz files so there's only
        # the 'make dist' tar.gz left in each directory.
        #
        FileUtils.rm_f Dir.glob("./*.tar.gz")

        hard_sh("make dist")

        # Rename the tarball's top directory from something like...
        #   memcached-1.4.4_232_g1859e39
        # to something like just..
        #   memcached.
        #
        FileUtils.rm_rf("#{cwd}/components/tmp/make_dist_tmp")
        FileUtils.mkdir_p("#{cwd}/components/tmp/make_dist_tmp")

        FileUtils.cp(Dir.glob("./*.tar.gz")[0], "#{cwd}/components/tmp/make_dist_tmp/#{n}.tar.gz")

        Dir.chdir("#{cwd}/components/tmp/make_dist_tmp")
        print "INFO: untgz of #{n} in " + Dir.cwd() + "\n"
        hard_sh("tar -xzf #{n}.tar.gz")
        FileUtils.rm_f("#{n}.tar.gz")

        # This is not just n, because ep-engine is sometimes inconsistently called epengine.
        #
        component_dir = Dir.glob("*")[0]

        hard_sh("mv #{component_dir} #{n}")
        hard_sh("tar -czf #{n}.tar.gz #{n}")

        FileUtils.mv("#{n}.tar.gz", "#{cwd}/components/tmp/make_dist/#{n}.tar.gz")
      end
    end
  end

  Dir.chdir(cwd)
end

task :components_make_dist_untgz do
  cwd = Dir.getwd()

  Dir.chdir("./components/tmp/make_dist")
  Dir.glob("*.tar.gz").each do |t|
    print "INFO: untgz of #{t} in " + Dir.cwd() + "\n"
    hard_sh("tar -xzf #{t}")
    FileUtils.rm_f(t)
  end

  dest_dir = ENV['dest_dir']
  if dest_dir
    Dir.glob("*").each do |t|
      FileUtils.rm_rf("#{cwd}/#{dest_dir}/#{t}")
      FileUtils.mv(t, "#{cwd}/#{dest_dir}")
    end
  end

  Dir.chdir(cwd)
end

desc "gen_dist_makefile out=./components/tmp/Makefile"
task :gen_dist_makefile do
  out = ENV['out'] || "./components/tmp/Makefile"

  print "INFO: generating #{out}\n"

  File.open(out, 'w') do |o|
    o.write("# Top-level Makefile for membase\n\n")

    COLLECT.each do |x|
      if x[:dist].class == String
        o.write("# #{x[:dist]}\n")
      end
    end
    o.write("# membase depends on erlang, version >= #{ERLANG_VER}\n")
    o.write("\n")

    o.write("default: build_configure\n\n")

    o.write("clean:\n")
    o.write("\trm -rf lib\n")
    COLLECT.each do |x|
      if x[:dist] != false and x[:dist].class != String and x[:dist_make] != false
        o.write("\t(cd #{x[:desc]} && $(MAKE) clean)\n")
      end
    end
    o.write("\n")

    o.write("build_configure:\n")
    o.write("\tmkdir -p lib\n")
    COLLECT.each do |x|
      if x[:dist] != false and x[:dist].class != String and x[:dist_make] != false
        autotools = ""
        if x[:dist_autotools]
          autotools = " && " + x[:dist_autotools]
        end

        configure = ""
        if x[:dist_configure] != false
          configure = " && ./configure"
          if x[:dist_configure]
            configure = configure + " " + x[:dist_configure]
          end
        end

        make = " && $(MAKE)"
        if x[:dist_make_install] != false
          make = make + " && $(MAKE) install"
        end

        o.write("\t(cd #{x[:desc]}#{autotools}#{configure}#{make})\n")
      end
    end
    o.write("\n")

    o.write("build:\n")
    COLLECT.each do |x|
      if x[:dist] != false and x[:dist].class != String and x[:dist_make] != false
        make = " && $(MAKE)"
        if x[:dist_make_install] != false
          make = make + " && $(MAKE) install"
        end

        o.write("\t(cd #{x[:desc]}#{make})\n")
      end
    end
    o.write("\n")

    o.write("run:\n")
    o.write("\t./ns_server/start.sh\n\n")
  end
end

# ---------------------------------------------

desc "optional flag to force ignoring of explicit Manifest versions"
task :latest_only do
  OPTS[:latest] = true # Get HEAD or latest, ignoring explicit Manifest versions.
end

desc "optional flag to build from local files/cache only, avoiding net access; usage: rake local_only latest"
task :local_only do
  OPTS[:local] = true
end

desc "optional flag to use github only, skipping the intranet git repo"
task :github_only do
  OPTS[:github_only] = true
end

desc "optional flag to only collect files and not actually build anything"
task :skip_make do
  OPTS[:skip_make] = true
end

# ---------------------------------------------

desc "build devkit mm"
task :build_devkit_mm do
  get_tmp("#{COMPANY}-devkit", true) # Clear out final staging tmp directory.
  build_product_mm('Server', 'DevKit')
  build_product_mm('DevKit', 'DevKit')
  build_product_mm('DevKit_docs', 'DevKit') if os_short() == 'win'
end

desc "build devkit installer"
task :build_devkit => [:build_devkit_mm] do
  build_product('DevKit')
end

# ---------------------------------------------

def build_server_mm(license_edition)
  FileUtils.cp("./components/EULA_server.#{license_edition}.txt",
               "./components/EULA_server.txt")
  FileUtils.cp("./components/EULA_server.#{license_edition}.txt",
               "./components/Server/LICENSE.txt")
  get_tmp("#{COMPANY}-server", true) # Clear out final staging tmp directory.
  build_product_mm('Server', 'Server')
  build_product_mm('Server_docs', 'Server') if os_short() == 'win'
end

desc "build server installer"
task :build_server do
  build_server_mm("community")
  build_product('Server', "couchbase-server-community")

  build_server_mm("enterprise-free")
  build_product('Server', "couchbase-server-enterprise")
end

# ---------------------------------------------

desc "collect components and make them"
task :collect do
  # Clear out previously collected / untar'ed *.tar.gz files,
  # but we keep the cached zip files (since we have them for more
  # static like content (docs)), and keep anything else marked
  # with :cache of true.
  #
  collected_before = Dir.glob("./components/tmp/collect_*.tar.gz")
  collected_cache = (COLLECT.map {|what|
                       if what[:cache]
                         Dir.glob("./components/tmp/collect_#{what[:name]}*.tar.gz")
                       else
                         []
                       end
                     }).flatten
  collected_clean = collected_before - collected_cache

  print "INFO: collected clean is #{collected_clean.join(', ')}\n"

  FileUtils.rm_rf(collected_clean)

  COLLECT.each do |what|
    if what[:desc]
      print "INFO: COLLECT: #{what[:desc]}\n"
    end

    result = nil
    after = what[:after]
    src = nil

    src_url  = src = what[:src_url]
    src_dir  = src = what[:src_dir]
    src_file = src = what[:src_file]
    src_tgz  = src = what[:src_tgz]
    src_zip  = src = what[:src_zip]
    src_lib  = src = what[:src_lib]
    step     = what[:step]

    if src_url
      result = collect_src_url(src_url, what[:dst_dir], what[:size],
                                        what[:src_alt])
    elsif src_dir
      result = collect_src_dir(src_dir, what[:dst_dir], what[:except], what[:force])
    elsif src_file
      result = collect_src_file(src_file,
                                what[:dst_dir], what[:src_alt], what[:dst_base])
    elsif src_tgz
      if src_tgz.class == Proc
        src_tgz = src_tgz.call(what)
      end
      result = collect_src_tgz(src_tgz)
    elsif src_zip
      result = collect_src_zip(src_zip)
    elsif src_lib
      result = collect_src_lib(src_lib)
      step.call(what)
    elsif step
      step.call(what)
    else
      print "WARNING: unknown collection type: #{what}\n"
    end

    if src and src.class == String
      $collected += [src]
    end

    after.call(what, result) if result and after
  end
end

task :post_collect do
  # Check if there are any text editor backup files here.
  drafts = Dir.glob('./components/**/*~')

  # Some autotools leave around harmless config.h.in~ files.
  drafts = drafts.delete_if {|x| x.match(/\/config.h.in~$/) }

  if drafts.length > 0
    print("ERROR: There are editor draft files here: #{drafts}\n")
    exit(1)
  end
end

# ---------------------------------------------

desc "generate files needed by installer"
task :gen_all => [:gen_versions, :gen_component_dims, :gen_component_specs]

desc "generate VERSION.txt files"
task :gen_versions => [:report_new] do
  collected = $collected.map {|x| File.basename(x)}
  collected += ["wallace_" + product_version]
  collected = collected.uniq.sort

  PRODUCT_NAMES.each do |x|
    File.open("./components/#{x}/VERSION.txt", 'w') do |o|
      o.write(product_version + "\n")
    end

    File.open("./components/#{x}/manifest.txt", 'w') do |o|
      collected.each {|y|
        if x.downcase != 'moxi' or MOXI_COMPONENTS.include?(y.split('_')[0].split('-')[0])
          o.write(y + "\n")
        end
      }
    end
  end
end

desc "generate component directory dim files"
task :gen_component_dims do
  trees = find_trees()
  Dir['./components/*.dim.erb'].each do |dim_src|
    dim_dst = dim_src.gsub(/.erb$/, '')
    dim_key = dim_dst.gsub(/.dim$/, '').gsub(/^.\/components\//, '')
    out = ERB.new(IO.read(dim_src)).result(binding)
    File.open(dim_dst, 'w') {|o| o.write(out)}
  end
end

desc "generate component directory spec files"
task :gen_component_specs do
  trees = find_trees()
  Dir['./components/*.spec.erb'].each do |spec_src|
    spec_dst = spec_src.gsub(/.erb$/, '')
    spec_key = spec_dst.gsub(/.spec$/, '').gsub(/^.\/components\//, '')
    out = ERB.new(IO.read(spec_src)).result(binding)
    File.open(spec_dst, 'w') {|o| o.write(out)}
  end
end

# --------------------------------------------------

desc "clean up ALL build artifacts"
task :clean_deep => [:clean] do
  deep = [
    "./components/*/*/*.zip",
    "./components/*/*/*.jar",
    "./components/*/*/*.tar",
    "./components/*/*/*.tar.gz",
    "./components/*/bin/erlang",
    "#{BASEX}"
  ]

  deep.each {|x| FileUtils.rm_rf(Dir.glob(x))}
end

desc "clean up fast changing build artifacts"
task :clean do
  %w[
     ./*.tar.gz
     ./**/*~
     ./**/#*#
     ./**/*.dump
     ./components/tmp
     ./components/*.dim
     ./components/*.spec
     ./components/*/VERSION.*
     ./components/*/VERSION_*.txt
     ./is_*/String*
     ./is_*/PROJECT_*
     ./is_*/Product*
     ./is_*/_ISUser*
     ./is_*/_isuser*
     ./is_*/setup.exe
     ./components/DevKit*/samples
     ./components/DevKit*/bin/*/
     ./components/DevKit*/bin/*.sh
     ./components/DevKit*/bin/*.bat
     ./components/Server*/bin/*/
     ./components/Server*/bin/*.sh
     ./components/Server*/bin/*.bat
     ./components/Server*/priv/config
     ./components/Moxi*/bin/*/
     ./components/Moxi*/bin/*.sh
     ./components/Moxi*/bin/*.bat
     ./components/*/lib/*/
     ./components/*/lib/*.zip
     ./components/*/lib/*.jar
     ./components/*/lib/*.gz
     ./components/*/docs
     ./components/*/docs/*
  ].each {|x| FileUtils.rm_rf(Dir.glob(x))}
end

task :hello do
  p "hello world"
end

# ------------------------------------------------------------

desc "will git-tag components used by wallace, so use with care"
task :tag_components do
  tag = ENV['tag']
  unless tag
    print "ERROR: need tag parameter. for example: rake tag_components tag=1.0.2\n"
    exit(1)
  end
  print "INFO: tag_components with tag: #{tag}\n"

  cwd = Dir.getwd()

  REPO_COMPONENTS_TAG.each do |pair|
    component = pair[0]
    branch = pair[1]
    print "INFO: tagging #{component} on branch #{branch} with #{tag}\n"
    Dir.chdir("../#{component}")
    hard_sh("git checkout #{branch}")
    hard_sh("git pull origin #{branch}")
    hard_sh("git fetch --tags")
    hard_sh("git tag -a #{tag} -m #{tag}")
    hard_sh("git push --tags")
  end

  Dir.chdir(cwd)
end

desc "synchronize internal/buildbot git repositories from github"
task :sync_git_repos do
  print "INFO: sync_git_repos\n"

  cwd = Dir.getwd()

  print "------------------------------\n"
  REPO_COMPONENTS.each do |pair|
    c = pair[0]
    branch = pair[1]
    print "#{c}...\n"
    hard_sh("curl http://builds.hq.northscale.net/~git/cgi/#{c}")
  end

  Dir.chdir(cwd)
end

# ------------------------------------------------------------

desc "runs git-describe on components used by wallace"
task :describe_components do
  print "INFO: describe_components\n"

  cwd = Dir.getwd()

  print "------------------------------\n"
  REPO_COMPONENTS.each do |pair|
    c = pair[0]
    branch = pair[1]
    print "#{c}...\n"
    Dir.chdir("../#{c}")
    hard_sh("git checkout #{branch}")
    hard_sh("git describe")
  end

  Dir.chdir(cwd)
end

desc "reports the changes in components since a previous tag"
task :report_component_changes do
  since_in = ENV['since']
  since_dt = ENV['since_date']
  until_in = ENV['until'] || 'HEAD'
  pull_in  = ENV['pull'] || 'yes'
  log_args = ENV['log_args'] || " --pretty=format:'%h %an %s' --abbrev-commit"

  unless (since_in or since_dt)
    print "ERROR: need since parameter. for example: rake report_component_changes since=1.0.0\n"
    print "ERROR: also: rake report_component_changes since=1.0.0 log_args=\"--pretty=fuller\"\n"
    print "ERROR: or: rake report_component_changes since_date=5/15/2010 log_args=\"--pretty=fuller\"\n"
    exit(1)
  end

  print "INFO: report_component_changes since: #{since_in || since_dt} until: #{until_in} log_args: #{log_args} pull: #{pull_in}\n"

  cwd = Dir.getwd()

  components = REPO_COMPONENTS

  if since_in
    components = REPO_COMPONENTS_TAG
  end

  def emit_info(component, branch, since_in, since_dt, until_in, log_args, pull_in)
    print "INFO: -----------------------------------------------------------\n"
    print "INFO: report_component_changes for: #{component} / #{branch} since: #{since_in || since_dt} until: #{until_in}\n"
    print "INFO: see https://github.com/#{COMPANY}/#{component}/tree/#{branch}\n\n"
  end

  def emit_log(component, branch, since_in, since_dt, until_in, log_args, pull_in)
    if pull_in != 'no'
      hard_sh("git pull origin #{branch}")
    end
    if since_in
      hard_sh("git log #{log_args} #{since_in}..#{until_in} | cat")
    else
      hard_sh("git log #{log_args} --since=#{since_dt} | cat")
    end
    print "\n\n"
  end

  components.each do |pair|
    component = pair[0]
    branch = pair[1]
    emit_info(component, branch, since_in, since_dt, until_in, log_args, pull_in)
    Dir.chdir("../#{component}")
    hard_sh("git checkout #{branch}")
    emit_log(component, branch, since_in, since_dt, until_in, log_args, pull_in)
  end

  Dir.chdir(cwd)

  emit_info("wallace", "master", since_in, since_dt, until_in, log_args, pull_in)
  emit_log("wallace", "master", since_in, since_dt, until_in, log_args, pull_in)
end

# ------------------------------------------------------------

desc "commit_hook"
task :commit_hook do
  cwd = Dir.getwd()

  COLLECT.each do |x|
    dist_repo = get_repo(x[:dist_repo] || x[:desc])

    if File.exists?(dist_repo + "/.git/hooks")
      print "#{dist_repo}\n"
      FileUtils.cp("./lib/commit-msg", dist_repo + "/.git/hooks")
    end
  end
end

# ------------------------------------------------------------

def py2exe(scriptToConvert)
  cwd = Dir.getwd()

  p = Pathname.new(scriptToConvert)

  Dir.chdir(p.dirname)

  x = "from distutils.core import setup\n" +
      "import py2exe\n" +
      "setup(console=['#{p.basename}'],\n" +
      "      options={'py2exe': {'bundle_files': 1}},\n" +
      "      zipfile=None)\n"

  File.open("dist_setup.py", 'w') {|fw| fw.write(x)}

  hard_sh("python dist_setup.py py2exe")

  FileUtils.cp_r(Dir.glob("dist/*"), ".")

  FileUtils.rm_rf("build")
  FileUtils.rm_rf("dist")
  FileUtils.rm_r("dist_setup.py")

  Dir.chdir(cwd)
end

# ------------------------------------------------------------

desc "report_new"
task :report_new do
  result = ''

  cwd = Dir.getwd()

  COLLECT.each do |x|
    name = x[:desc]
    repo = get_repo(name)

    if File.directory?(repo)
      tag = component_tag(name)
      if tag
        print("INFO: previous #{name} #{tag}\n")

        Dir.chdir(repo)
        result = result + "---- #{name}\n"
        result = result + `git log --pretty=format:'%h %an, %s' --abbrev-commit #{tag}..HEAD --`
        result = result + "\n"
        Dir.chdir(cwd)
      end
    end
  end

  Dir.chdir(cwd)

  tag = component_tag('wallace')
  if tag
    result = result + "---- wallace\n"
    result = result + `git log --pretty=format:'%h %an, %s' --abbrev-commit #{tag}..HEAD --`
    result = result + "\n"
  end

  File.open("./CHANGES.txt", 'w') do |o|
    o.write("# changes from last build to #{product_version}\n")
    o.write(result)
  end
end


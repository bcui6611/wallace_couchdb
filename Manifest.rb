# Currently, product versions (devkit vs server) are locksteped with
# each other.
#
# The PRODUCT_VERSION will look like:
#
#    1.0.0-1-gfa234g1_win32
#    1.0.0-1-gfa234g1_win64
#    1.0.0-1-gfa234g1_osx
#
PRODUCT_GIT_DESCRIBE = git_describe()

GITPRIV = "git://10.1.1.210"
GITHUB  = "git@github.com:membase"

PRODUCT_NAMES = ['Server']

# grommit holds slow-changing dependencies, such as 3rd-party compilers,
# libraries or other resources.
#
# grommix is a caching directory to help wallace re-build faster
# reusing work from previous runs.
#
# This Manifest.rb assumes that the grommit and grommix subdirectories
# are siblings of the wallace subdirectory.
#
BASE = "../grommit_couchdb"
BASEX = "../grommix"

if (not File.exists?("#{BASEX}"))
  FileUtils.mkdir_p("#{BASEX}")
end

if (not File.exists?("#{BASE}"))
  print "ERROR: You need to check out grommit before trying to build wallace\n"
  exit(1)
end

# Note, the erlang version is also hardcoded in the .ism/.rul
# files on windows.
#
ERLANG_VER = '5.7.4'

# ------------------------------------------------

print("info: manifest: ./Manifest_VERSION.rb\n")
load("./Manifest_VERSION.rb")

if File.exists?("./Manifest_VERSION_local.rb")
  print("info: manifest: ./Manifest_VERSION_local.rb\n")
  load("./Manifest_VERSION_local.rb")
end

# ------------------------------------------------

# Note: some repos are not in REPO_COMPONENTS_TAG because they
# have their own tagging scheme.
#
REPO_COMPONENTS_TAG = [
# [ repo name,                 repo branch]
  ['grommit',                  'master'],
  ['couchdb',                  'refresh']
]

REPO_COMPONENTS = REPO_COMPONENTS_TAG.clone().concat([
  ['memcached', 'engine'] # TODO: Recheck if this should be something else.
])


# ------------------------------------------------

# This sections lists slowly changing component projects, or projects
# which we cannot tag due to a different tag namespace.
#
VERSION_PTHR_WIN32 = "2_9_0_0"
VERSION_PTHR_WIN64 = "2-8-0-release"

LIBEVENT_VERSION = "2.0.7-rc"

CURL_VERSION = "7.21.1-w64_patched"

# ------------------------------------------------

def base_tmp_install()
  t = base_tmp_dir(BASEX, 'install')
  FileUtils.mkdir_p(t + "/bin")
  FileUtils.mkdir_p(t + "/include")
  FileUtils.mkdir_p(t + "/lib")
  FileUtils.mkdir_p(t + "/share")
  return t
end

def base_tmp_dir(base, name, version=nil)
  if version
    Pathname.new(base).realpath().to_s() + "/#{name}-#{version}"
  else
    Pathname.new(base).realpath().to_s() + "/#{name}"
  end
end

# ------------------------------------------------

def autorun_cmd(repo_name)
  ["./config/autorun.sh"]
end

def autosave_cmd(repo_name, extras="")
  ["mkdir -p #{STARTDIR}/components/autogen/#{repo_name}",
   "cp -R Makefile* ac* conf* m4 #{extras} #{STARTDIR}/components/autogen/#{repo_name}"]
end

# ------------------------------------------------

def configure_flags
  ""
end

def make_flags
  ""
end

def curl_test
  "#{base_tmp_install()}/lib/libcurl.a"
end

def curl_configure_flags
  "--disable-shared"
end

def licenses_file
  "licenses_20101221.tgz"
end

# ------------------------------------------------

PRODUCT_VERSION = PRODUCT_GIT_DESCRIBE + '-' + product_platform()
PRODUCT_VERSION_PREFIX = PRODUCT_VERSION.split('-')[0]

load("./Manifest_#{os_short}.rb")


# ------------------------------------------------

COLLECT_INDEPENDENT =
  [
    { :desc => "licenses",
      :dist => false,
      :seq => 50,
      :src_file => "#{BASE}/#{licenses_file()}",
      :dst_dir => "./components/Server",
      :dst_base => "licenses.tgz"
    },
    { :desc => "platform/bin",
      :dist => false,
      :seq => 20,
      :src_dir => "./components/platform_#{os_general()}/bin",
      :dst_dir => "./components/Server/bin",
      :force => true
    }
  ]


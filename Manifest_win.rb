# Do OS specific things here.
#
def product_platform()
  os_short + os_nbits
end

def win_make_flags()
  ""
end

def pthread_install
  "/usr"
end

def vbucketmigrator_configure_flags
end

def curl_test
  "#{base_tmp_install()}/bin/libcurl-4.dll"
end

def curl_configure_flags
  # Do not use --disable-shared for curl on windows,
  # because curl_easy_setopts() seems to go missing.
  ""
end

def licenses_file
  "licenses_win_20101221.tgz"
end

# ------------------------------------------------

# We don't have auto* tools on windows, so we need to copy
# pre-generated files (from some other system) instead.

def autorun_cmd(repo_name)
  ["cp -Rf #{STARTDIR}/components/autogen/#{repo_name}/* .",
   "touch Makefile"]
end

def autosave_cmd(repo_name, extras="")
  []
end

# ------------------------------------------------

load("./Manifest_win#{os_nbits}.rb")

COLLECT_PLATFORM_WIN =
  [
    { :desc => "erlang",
      :seq => 30,
      :src_dir => "/#{builder_erlang_dir()}",
      :dist => false,
      :force => true,
      :dst_dir => "components/Server",
      :except => [/.*\/doc/,
                  /.*\/usr/,
                  /.*\/src/,
                  /.*\/examples/,
                  /.*\/include/,
                  /.*\/Install/,
                  /.*\/Uninstall/,
                  /.*\/lib\/cos/,
                  /.*\/lib\/asn1-/,
                  /.*\/lib\/edoc-/,
                  /.*\/lib\/gs-/,
                  /.*\/lib\/ic-/,
                  /.*\/lib\/jinterface-/,
                  /.*\/lib\/megaco-/,
                  /.*\/lib\/orber-/,
                  /.*\/lib\/toolbar-/,
                  /.*\/lib\/wx-/,
                 ]
    },
    { :desc => "vcredist",
      :seq =>32,
      :src_file => "/#{builder_erlang_dir()}/vcredist_x86.exe",
      :src_alt  => "#{BASE}",
      :dist => false,
      :dst_dir  => "components/Server/bin/erlang"
    },
    { :desc => "couchdb",
      :seq => 100,
      :src_tgz => pull_make("#{BASEX}", "couchdb", VERSION_COUCHDB, "tar.gz",
                            { :os_arch => false,
                              :branch => "origin/master",
                              :premake => autorun_cmd("couchdb") +
                                          ["sh ./configure --prefix=#{STARTDIR}/components/Server" +
                                                         " --with-js-include=#{base_tmp_install}/include/spidermonkey"+
                                                         " --with-js-lib=#{base_tmp_install}/lib/spidermonkey" +
                                                         " --with-win32-icu-binaries=#{STARTDIR}/#{BASE}/icu4c-4_2_1-Win32-msvc9/icu" +
                                                         " --with-erlang=#{builder_erlang_base()}/#{builder_erlang_dir()}/usr/include" +
                                                         " --with-win32-curl=#{STARTDIR}/#{BASE}/curl-7.20.1" +
                                                         " --with-msvc-redist-dir=#{STARTDIR}/#{BASE}/vcredist_x86.exe" +
                                                         " --with-msbuild-dir=#{DOTNET_FRAMEWORK_4}"],
                              :make => ["make -e LOCAL=#{base_tmp_install()}",
                                        "make install",
                                        "make --file=#{STARTDIR}/components/Makefile.couchdb_extra SRC_DIR=#{STARTDIR}/components/Server bdist"]
                            }),
      :dst_dir => "components/Server",
      :after   => mv_dir_proc()
    }
  ]

COLLECT_PLATFORM = COLLECT_PLATFORM_WIN.clone().concat(COLLECT_PLATFORM_WIN_BITSIZE_SPECIFIC)

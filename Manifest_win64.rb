# Do win64 OS specific things here.
#
def make_flags
  " -e CC=\"x86_64-w64-mingw32-gcc -std=gnu99\"" +
  " -e CXX=x86_64-w64-mingw32-g++" +
  " -e MARCH="
end

def win_make_flags()
  make_flags
end

def configure_flags
  " --host=x86_64-w64-mingw32 --build=i686-pc-mingw32"
end

def vbucketmigrator_configure_flags
  " CC=\"x86_64-w64-mingw32-gcc -std=gnu99\"" +
  " CXX=x86_64-w64-mingw32-g++"
end

def pthread_install
  t = base_tmp_dir(BASEX, 'install')
  # The win64 cc stop is arpa/inet.h doesn't exist, unlike win32 cc.
  FileUtils.mkdir_p(t + "/include/arpa")
  FileUtils.touch(t + "/include/arpa/inet.h")
  t.gsub(/^c:/, "/c")
end

def base_tmp_install()
  t = base_tmp_dir(BASEX, 'install')
  FileUtils.mkdir_p(t + "/bin")
  FileUtils.mkdir_p(t + "/include")
  FileUtils.mkdir_p(t + "/lib")
  FileUtils.mkdir_p(t + "/share")
  t.gsub(/^c:/, "/c")
end

COLLECT_PLATFORM_WIN_BITSIZE_SPECIFIC = [
    # Requires pre-built pthreads to be installed in /mingw64
    # per instructions at...
    #
    #   http://wiki.membase.org/bin/view/Main/MembaseSourceWindows
    #   http://sourceforge.net/projects/mingw-w64/files/ \
    #     External%20binary%20packages%20(Win64%20hosted)/ \
    #     pthreads/pthreads-20100604.zip/download
    #
    # So we're skipping a true pthreads make...
    #
    { :desc => "pthreads-win",
      :seq  => -100, # This collect step runs early, before libevent is built.
      :step => src_make("#{BASE}", "pthreads-w64-" + VERSION_PTHR_WIN64 + ".tar.gz",
                         { :skip_file => true,
                           :os_arch => true,
                           :test => "#{pthread_install}/lib/pthreadGC2-w64.dll",
                           :make => [ "cp /mingw64/bin/pthreadGC2-w64.dll #{pthread_install}/bin",
                                      "cp /mingw64/bin/pthreadGC2-w64.dll #{pthread_install}/lib",
                                      "cp /mingw64/x86_64-w64-mingw32/include/*.h #{pthread_install}/include",
                                      "cp /mingw64/x86_64-w64-mingw32/lib/libpthread*.a #{pthread_install}/lib",
                                      "cp /c/mingw/bin/w64gcc_s_sjlj-1.dll #{pthread_install}/bin",
                                      "cp /c/mingw/bin/w64gcc_s_sjlj-1.dll #{pthread_install}/lib",
                                      "cp /c/mingw/bin/libstdc++-6.dll #{pthread_install}/bin",
                                      "cp /c/mingw/bin/libstdc++-6.dll #{pthread_install}/lib"
                                     ]
                         })
    }
]


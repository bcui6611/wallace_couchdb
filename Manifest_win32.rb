# Do win32 OS specific things here.
#
COLLECT_PLATFORM_WIN_BITSIZE_SPECIFIC = [
    { :desc => "pthreads-win",
      :seq  => -100, # This collect step runs early, before libevent is built.
      :step => pull_make("#{BASE}", "pthreads-win", VERSION_PTHR_WIN32, "tar.gz",
                         { :branch => "origin/win32",
                           :skip_file => true,
                           :os_arch => true,
                           :test => "#{pthread_install}/lib/pthreadGC2.dll",
                           :make => ["make clean GC",
                                      "cp pthreadGC2.dll #{pthread_install}/lib",
                                      "cp pthreadGC2.dll #{pthread_install}/lib/pthread.dll",
                                      "cp pthread.h #{pthread_install}/include",
                                      "cp sched.h #{pthread_install}/include",
                                      "cp semaphore.h #{pthread_install}/include",
                                      "cp implement.h #{pthread_install}/include"
                                     ]
                         })
    }
]

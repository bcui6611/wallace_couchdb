set CB_BIN=%~dp0
set CB_ROOT=%CB_BIN%..
set CB_ERTS=%CB_BIN%erts-5.7.4\bin

"%CB_ERTS%\erlsrv.exe" stop CouchbaseServer

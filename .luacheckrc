stds.redbean = {
    read_globals = {"arg", "Write", "OnHttpRequest", "OnClientConnection", "OnLogLatency", "OnProcessCreate", "OnProcessDestroy", "OnServerHeartbeat", "OnServerListen", "OnServerStart", "OnServerStop", "OnWorkerStart", "OnWorkerStop", "SetStatus", "SetHeader", "SetCookie", "GetParam", "EscapeHtml", "LaunchBrowser", "CategorizeIp", "DecodeBase64", "DecodeLatin1", "EncodeBase64", "DecodeJson", "EncodeJson", "EncodeLua", "EncodeLatin1", "EscapeFragment", "EscapeHost", "EscapeLiteral", "EscapeParam", "EscapePass", "EscapePath", "EscapeSegment", "EscapeUser", "EvadeDragnetSurveillance", "Fetch", "FormatHttpDateTime", "FormatIp", "GetRmoteAddr", "GetResponseBody", "GetClientAddr", "GetServerAddr", "GetDate", "GetHeader", "GetHeaders", "GetLogLevel", "GetHost", "GetHostOs", "GetMonospaceWidth", "GetMethod", "GetParams", "GetPath", "GetEffectivePath", "GetScheme", "GetPayload", "GetStatus", "GetTime", "GetUrl", "GetHttpVersion", "GetHttpReason", "GetRandomBytes", "GetRedbeanVersion", "GetZipPaths", "HasParam", "HidePath", "IsHiddenPath", "IsPublicIp", "IsPrivateIp", "IsLoopbackClient", "IsLoopbackIp", "IsAssetCompressed", "IndentLines", "LoadAsset", "StoreAsset", "Log", "ParseHttpDateTime", "ParseHttpDateTime", "ParseUrl", "IsAcceptablePath", "IsReasonablePath", "EncodeUrl", "ParseIp", "GetAssetComment", "GetAssetLastModifiedTime", "GetAssetMode", "GetAssetSize", "GetBody", "GetCookie", "Md5", "Sha1", "Sha224", "Sha256", "Sha384", "Sha512", "GetCryptoHash", "IsDaemon", "ProgramAddr", "ProgramGid", "ProgramDirectory", "ProgramLogMessages", "ProgramLogBodies", 'ProgramLogPath', "ProgramPidPath", "ProgramUniprocess", "Slurp", "Barf", "ProgramContentType", "ProgramHeader", "ProgramHeartbeatInterval", "ProgramTimeout", "ProgramSslTicketLifetime", "ProgramBrand", "ProgramCache", "ProgramPort", "ProgramMaxPayloadSize", "ProgramRedirect", "ProgramCertificate", "ProgramMaxWorkers", "ProgramPrivateKey", "ProgramSslPresharedKey", "ProgramSslFetchVerify", "ProgramSslClientVerify", 'ProgramSslRequired', "ProgramSslCiphersuite", "Route", "Sleep", "RouteHost", "RoutePath", "ServeAsset", "ServeError", "SetLogLevel", "VisualizeControlCodes", "Underlong", "Bsf", "Bsr", "Crc32", "Crc32c", "Popcnt", "Rdtsc", "Lemur64", "Rand64", "Rdseed", "GetCpuCount", "GetCpuCore", "GetCpuNode", "Decimate", "MeasureEntropy", "Deflate", "Inflate", "Benchmark", "oct", "hex", 'bin', "ResolveIp", "IsTrustedIp", "ProgramTrustedIp", "ProgramTokenBucket", "AcquireToken", "Blackhole", unix = {
        fields = {
            "clock_gettime", "gmtime", "F_OK", "access"
        }
    }, "kLogDebug", "kLogVerbose", "kLogInfo", "kLogWarn", "kLogError", "kLogFatal", re = {
        fields = {
            "compile"
        }
    }},
    globals = {"db", "re", "AT_URI", "DB_FILE", "GetProfileFromCache",
    "PutProfileIntoCache", "getFromProfileCacheStmt", "insertIntoProfileCacheStmt",
    "SetupSql", "SetupDb", "sqlite3", "getFromPostCacheStmt", "insertIntoPostCacheStmt",
    "GetPostFromCache", "PutPostIntoCache"}
}
std = "lua54+redbean"

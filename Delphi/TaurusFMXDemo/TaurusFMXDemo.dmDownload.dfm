object dmDownload: TdmDownload
  Height = 480
  Width = 640
  object cliHTTP: TIdHTTP
    Intercept = logFTP
    IOHandler = iohTLS
    OnWork = ClientWork
    OnWorkBegin = HTTPWorkBegin
    HandleRedirects = True
    RedirectMaximum = 9
    ProxyParams.BasicAuthentication = False
    ProxyParams.ProxyPort = 0
    Request.ContentLength = -1
    Request.ContentRangeEnd = -1
    Request.ContentRangeStart = -1
    Request.ContentRangeInstanceLength = -1
    Request.Accept = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    Request.BasicAuthentication = False
    Request.UserAgent = 'Mozilla/3.0 (compatible; Indy Library)'
    Request.Ranges.Units = 'bytes'
    Request.Ranges = <>
    HTTPOptions = [hoForceEncodeParams]
    OnHeadersAvailable = HTTPHeaders
    OnRedirect = HTTPRedirect
    Left = 48
    Top = 56
  end
  object cliFTP: TIdFTP
    Intercept = logFTP
    IOHandler = iohTLS
    OnWork = ClientWork
    Passive = True
    ConnectTimeout = 15000
    TransferType = ftBinary
    NATKeepAlive.UseKeepAlive = False
    NATKeepAlive.IdleTimeMS = 0
    NATKeepAlive.IntervalMS = 0
    ProxySettings.ProxyType = fpcmNone
    ProxySettings.Port = 0
    ReadTimeout = 15000
    Left = 112
    Top = 56
  end
  object iohTLS: TTaurusTLSIOHandlerSocket
    Destination = ':21'
    Intercept = logFTP
    MaxLineAction = maException
    Port = 21
    DefaultPort = 0
    ReadTimeout = 15000
    OnSSLNegotiated = TLSNegotiated
    SSLOptions.Mode = sslmClient
    SSLOptions.VerifyMode = [sslvrfPeer]
    SSLOptions.VerifyDepth = 100
    OnVerifyCallback = TLSVerify
    Left = 248
    Top = 56
  end
  object logFTP: TTaurusTLSUnicodeLog
    Active = True
    OnReceived = FTPReceived
    OnSent = FTPSent
    Left = 176
    Top = 56
  end
end

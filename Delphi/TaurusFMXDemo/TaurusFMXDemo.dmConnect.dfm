object dmConnect: TdmConnect
  Height = 480
  Width = 640
  object ttslLoader: TTaurusTLSLoader
    PlatformSettings = <
      item
        Target = tlpWindows32
        ConfigFile = '..\..\conf\openssl-win.cnf'
      end
      item
        Target = tlpWindows64
        ConfigFile = '..\..\conf\openssl-win.cnf'
      end
      item
        Target = tlpMacOS
        ConfigFile = 'conf/openssl-osx.cnf'
      end
      item
        Target = tlpLinux
        ConfigFile = 'conf/openssl-linux.cnf'
      end
      item
        Target = tlpAndroid
        ConfigFile = 'conf/openssl-android.cnf'
      end
      item
        Target = tlpiOS
        ConfigFile = 'conf/openssl-ios.cnf'
      end>
    LoadOnStart = False
    Left = 144
    Top = 192
  end
end

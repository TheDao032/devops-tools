module OS
  def OS.windows?
    (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM) != nil
  end

  def OS.mac?
    (/darwin/ =~ RUBY_PLATFORM) != nil
  end

  def OS.unix?
    !OS.windows?
  end

  def OS.linux?
    OS.unix? and not OS.mac?
  end

  def OS.jruby?
    RUBY_ENGINE == "jruby"
  end
end

module Utils
  include OS

  def get_bridge_adapter(provider)
    if OS.windows?
      return %x{powershell -Command "Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Get-NetAdapter | Select-Object -ExpandProperty InterfaceDescription"}.chomp
    elsif OS.linux?
      return %x{ip route | grep default | awk '{ print $5 }'}.chomp
    elsif OS.mac?
      return %x{configuration/networks/#{provider}/macos/macos-bridge.sh}.chomp
    end
  end
end

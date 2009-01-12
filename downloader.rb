require 'rubygems'
require 'net/http'
require 'uri'
require 'plist'
require 'time'

class Downloader
  attr_reader :running
  def initialize
    @running = []
    
    if File.exists?("rapidshare.cookie")
      @cookie = open("rapidshare.cookie").read
    else
      # Need to make this work for other operating systems / users
      Plist::parse_xml("/Users/jp/Library/Cookies/Cookies.plist").each do |hash|
        if hash['Domain'] =~ /rapidshare\.com$/
          @cookie = "user="+hash['Value']
          break
        end
      end
      open("rapidshare.cookie","w").print @cookie
    end
  end
  
  def start(name,url,dest,f_afterhead = nil)
    # Fix this so it does resuming if a download was stopped half way through
    if File.exists? dest
      f_afterhead.call(dest)
      return
    end
    status = {:name=>name,:complete=>0,:size=>nil,:started=>Time.new.to_i}
    @running.push(status)
    path = URI.parse(url)
    
    download = open(dest,"w")
    
    dohead = (f_afterhead.nil?) ? false : true
        
    req = Net::HTTP::Get.new(path.path)
    req.add_field("Cookie",@cookie)
    req.add_field("User-agent",$useragent)

    # Get the redirect
    Net::HTTP.start(path.host, path.port) {|http|
      http.request(req) {|res|
        url = res['location']
      }
    }
    
    path = URI.parse(url)

    req = Net::HTTP::Get.new(path.path)
    req.add_field("Cookie",@cookie)
    req.add_field("User-agent",$useragent)
    
    Net::HTTP.start(path.host, path.port) {|http|
      http.request(req) {|res|
        status[:size] = res.content_length
        res.read_body do |chunk|
          download.write chunk
          status[:complete] = download.pos
          
          if dohead and download.pos > 128 #got enough of the rar archive to test it
            f_afterhead.call(dest)
            dohead = false
          end
        end
      }
    }
    download.close
    @running.delete(status)
  end
end
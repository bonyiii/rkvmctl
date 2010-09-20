#!/usr/bin/env ruby
require 'net/telnet'

#We start debbuger with these options
#require 'rubygems'
#require 'ruby-debug'
#Debugger.start

class RKvmctl
  BRCTL='/sbin/brctl'
  SUDO='/usr/bin/sudo'
  QEMU='/usr/bin/qemu-kvm'
  MODPROBE='/sbin/modprobe'
  LSMOD='/sbin/lsmod'
  IFCONFIG='/sbin/ifconfig'
  DHCLIENT='/sbin/dhclient'
  PIDDIR='/var/run/kvm'
  KILL='/bin/kill'
  MKDIR='/bin/mkdir'
  RM='/bin/rm'
  PGREP='/usr/bin/pgrep'
  GREP='/usr/bin/grep'
  AWK='/usr/bin/awk'
  BRIDGE_NAME='br0'
  KERNEL_MODULE_NAME='kvm_amd' #'kvm_intel'
  CAT='/bin/cat'
  VNCVIEWER='/usr/bin/vncviewer'
  
  def initialize(params)
    @scriptname=File.basename($0)
    #should be changed by params
    @verbose=true
    @defaults={
      "sleeptime"=>3,
      # How long to sleep at certain points in the script
      "sleeptries"=>10,
      # How many times wait sleeptime for shutdown
      "monitor_port"=>4000,
      #Makes shutdown avaiable
      "monitor_redirect"=>true,
      #Display type for VGA output
      "display"=>"vnc"
      
    }
    uid_check
  end
#NO CHANGE SHOULD BE NECCESSARY BELOW THIS LINE
  
  def start(filename)
    return false unless conf_load(filename)==true
    kernel_module_start
    bridge_start
    `#{@mkdir} #{PIDDIR}` unless File.exist?(PIDDIR)
    
    #net nic
    macaddress=",macaddr="+@conf["macaddress"] if @conf.include?("macaddress")
    model=",model="+@conf["model"] if @conf.include?("model")
    vlan="" # TODO remove this line, use the line below
    #vlan=",vlan="+@conf["vlan"] if @conf.include?("vlan")
    #nic="-net nic"+@conf["nic"]+macaddress.to_s+vlan.to_s #if @conf.include?("nic")
    nic="-net nic"+macaddress.to_s+model.to_s+vlan.to_s
    
    #net tap
    ifname=",ifname="+@conf["ifname"] if @conf.include?("ifname")
    script=",script="+@conf["script"]if @conf.include?("script")
    tap="-net "+@conf["tap"]+ifname.to_s+script.to_s+vlan.to_s if @conf.include?("tap")
    
    hda="-hda "+@conf["hda"]
    hdb="-hdb "+@conf["hdb"] if @conf.include?("hdb")
    hdc="-hdc "+@conf["hdc"] if @conf.include?("hdc")
    hdd="-hdd "+@conf["hdd"] if @conf.include?("hdd")
    boot="-boot "+@conf["boot"]
    cdrom="-cdrom "+@conf["cdrom"] if @conf.include?("cdrom")
    cpus="-smp "+@conf["cpus"] if @conf.include?("cpus")
    vnc_port=" -vnc :"+@conf["id"] if @conf.include?("id") && @conf["display"]=="vnc"
    keyboard="-k "+@conf["keyboard"] if @conf.include?("keyboard")
    soundhw="-soundhw "+@conf["soundhw"] if @conf.include?("soundhw")
    daemonize="-daemonize" if @conf.include?("daemonize") && (@conf["daemonize"]=="true" || @conf["daemonize"].to_i==1)
    #later other usb devices can be added, the -usb activate the usb driver
    if @conf["display"]!="sdl"
      usb="-usb "
      usbdevice="-usbdevice "+@conf["mouse"]
    end
    pidfile="-pidfile #{get_pidfile(filename)}"
    mem="-m "+@conf["mem"] if @conf.include?("mem")
    noacpi="-no-acpi" if @conf.include?("noacpi") && @conf["noacpi"]==1
    nographic="-nographic" if @conf.include?("graphic") && @conf["graphic"]==0
    monitor="-monitor telnet:127.0.0.1:#{@conf["monitor_port"]},server,nowait" if @conf["monitor_redirect"]!="false" && @conf.include?("monitor_port")
    #puts vnc_port
    #exit
    
    command="#{@qemu} #{mem} #{hda} #{hdb} #{hdc} #{hdd} #{cdrom} #{boot} #{nic} #{tap} #{cpus} #{vnc_port} #{daemonize} #{keyboard} #{soundhw} #{usb} #{usbdevice} #{pidfile} #{monitor} #{noacpi} #{nographic}"
    puts command if @verbose
    `#{command}`
  end
  
  def stop(filename)
    #return false unless conf_load(filename)==true
    pid=get_pid(filename)
    if pid=~ /\d+/
      `#{@kill} -TERM #{pid}`
      `#{@rm} #{get_pidfile(filename)}`
      return true
    else
      puts "There is no such vm running..."
      return false
    end
    #bridge_stop
  end
  
  def shutdown(filename)
    return false unless conf_load(filename)==true
    print "Shutting down"
    STDOUT.flush
    server = Net::Telnet::new('Host'=>'localhost','Port'=>@conf["monitor_port"].to_i,'Telnetmode'=>false)
    server.write("system_powerdown\n")
    sleep @conf["sleeptime"]
    @conf["sleeptries"].to_i.times do
      if File.exist?("/proc/#{get_pid(filename)}")
        sleep @conf["sleeptime"]
      else
        `#{@rm} #{get_pidfile(filename)}`
        puts " Finished!"
        return true
      end
      print "."
      STDOUT.flush
    end
    puts " Failed!"
    return false
  end
  
  def vnc(filename)
    if Process.uid==0 
      print "Do you really want to run vncviewer as root (y/n) "
      while input = STDIN.gets and !(input.chomp =~ /[YynN]/)
        print "Do you really want to run vncviewer as root (y/n) "
      end
      return false if input.chomp.downcase == 'n'
    end
    `#{VNCVIEWER} localhost:#{get_vnc_port(filename)}> /dev/null 2>&1 &`
    return true
  end
  
  #Possible alternate is stop-start
  def restart(filename)
    start (filename) if shutdown(filename) == true
  end
  
  def bridge_stop
    if env_check("#{@brctl} show","#{BRIDGE_NAME}.*")==true
      `#{@ifconfig} #{BRIDGE_NAME} down`
      `#{@brctl} delif #{BRIDGE_NAME} eth0`
      `#{@brctl} delbr #{BRIDGE_NAME}`
      `#{@dhclient} eth0`
      puts "Bridge stopped." if @verbose
    else
      puts "Bridge doesn't run." if @verbose
    end  
  end 
  
  def kernel_module_stop
    if env_check("#{@lsmod}","^#{KERNEL_MODULE_NAME}.*")==true
      `#{@modprobe} -r #{KERNEL_MODULE_NAME}`
      puts "Kernel module unloaded." if @verbose
      #here should be another check whether the unload was successful?
    else
      puts "Kernel module isn't loaded." if @verbose
    end  
  end 
  
  def status(vm_name)
    if vm_name==nil
      puts "Currently running virtual machines:\n"
      #puts `#{PGREP} -lf kvm | #{GREP} -v #{@scriptname} | #{AWK} '\{ print $4 \}'`
	`#{PGREP} -lf kvm | #{GREP} -v #{@scriptname}`.each do 
		|line| print line.slice(/^\d+/)+" "
		puts line.slice(/(\w+-\w+)(\.pid)/,1)
	end
    elsif vm_name=="kvm"
      puts `#{PGREP} -lf kvm | #{GREP} -v #{@scriptname}`
    end
  end
  
  def help
    #quick ruby reference http://www.zenspider.com/Languages/Ruby/QuickRef.html
    scriptversion=1.0
    help_text=<<end_of_help
        #{@scriptname} #{scriptversion}
        Licensed under BSDL  Copyright:      2008
        #{@scriptname} is a management and control script for KVM-based virtual machines.
        Usage:  #{@scriptname} --start          host - start the named VM
                #{@scriptname} --stop             host - stop  the named VM (only use if the guest is hung)
                #{@scriptname} --shutdown         host - stop  the named VM gracefully (only works if acpid is running in vm)
                #{@scriptname} --vnc              host - connect vncviewer to named vm
                #{@scriptname} --restart          host - start the named VM, and then connect to console via VNC
                #{@scriptname} --bridge-stop         - stop bridged networking and set it back as it was
                #{@scriptname} --kernel-module-stop  - unload kvm kernel module
                #{@scriptname} --status              - show the names of all running VMs
                #{@scriptname} --status         kvm  - show full details for all running kvm processes
                #{@scriptname} --help                - show this usage blurb
        ** Using stop is the same as pulling the power cord on a physical system. Use with caution.
end_of_help
    puts help_text
  end
  
  def usage
    puts "\nType #{@scriptname} --help to see available commands!\n\n"
    return false
  end
  
  private
  
  def get_pid(filename)
    if File.exist?(get_pidfile(filename))
      pid=%x{#{@cat} #{get_pidfile(filename)}}.slice(/\d+/)  
    else
      pid=`#{PGREP} -lf #{get_pidfile(filename)} | #{GREP} -v #{@scriptname} | #{AWK} '\{ print $1\}'`.slice(/\d+/)
    end
  end
  
  #Returns the pidfile to identify the process, the pidfile always present in pgrep since this program always sets a pidfile
  def get_pidfile(filename)
    "#{PIDDIR}/#{File.basename(filename)}.pid"
  end
  
  #
  def get_vnc_port(filename)
    `#{PGREP} -lf #{get_pidfile(filename)} | #{GREP} -v #{@scriptname}`.slice(/(-vnc) :(\d+)/,2)
  end
  
  def conf_load(filename)
    @conf={}
    unless !filename.nil? && File.exist?(filename)
      puts "Config file '#{filename}' doesn't exists!" 
      return false
    end

    @defaults.each do |key,variable|
      @conf[key]=variable
    end

    File.open(filename).each do |line|
      if line=~/^\w+/
        variable=line.split("=")
        @conf[variable[0]]=variable[1].slice(/[\w\/\.\:-]+/)
        #puts variable[0]+" "+variable[1]
      end
    end
    @conf["monitor_port"]=@defaults["monitor_port"]+@conf["id"].to_i if @conf["monitor_port"].nil?
    return true
  end
  
  def uid_check
    sudo= Process.uid==0 ? "" : SUDO+" "
    RKvmctl.constants.each do |constant|
      instance_variable_set("@#{constant}".downcase,sudo+RKvmctl.const_get(constant)) unless constant=="SUDO"
    end
  end
  
  def env_check(command, regexp)
    %x{#{command}}.each do |line|
      return true if line =~ /#{regexp}/ 
    end
    return false
  end
  
  #Starts the bridge, setup eth0, connect eth0 to bridge, get ip for br0
  def bridge_start
    if env_check("#{@brctl} show","#{BRIDGE_NAME}.*")==false
      `#{@brctl} addbr #{BRIDGE_NAME}`
      `#{@ifconfig} eth0 0.0.0.0 promisc up`
      sleep 0.5
      `#{@brctl} addif #{BRIDGE_NAME} eth0`
      `#{@dhclient} #{BRIDGE_NAME}`
      `sudo pkill dhcpcd`
      #`/sbin/dhcpcd -D -K -N -t 999999 -h bear.home -c /etc/sysconfig/network/scripts/dhcpcd-hook #{BRIDGE_NAME}`
      puts "Bridge started." if @verbose
    else
      puts "Bridge is already running." if @verbose
    end  
  end
  
  def kernel_module_start
    if env_check("#{@lsmod}","^#{KERNEL_MODULE_NAME}.*")==false
      `#{@modprobe} #{KERNEL_MODULE_NAME}`
      sleep 0.5
      puts "Kernel module loaded."
    else
      puts "Kernel module already loaded."
    end  
  end
end


#Program starts...
if defined?(ARGV)
  vm=RKvmctl.new("")
  case (ARGV[0])
    when '--start'
    vm.start(ARGV[1])
    when '--restart'
    vm.restart(ARGV[1])
    when '--stop'
    vm.stop(ARGV[1])
    when '--shutdown'
    vm.shutdown(ARGV[1])
    when '--status'
    vm.status(ARGV[1])
    when '--bridge-stop'
    vm.bridge_stop
    when '--vnc'
    vm.vnc(ARGV[1])
    when '--kernel-module-stop'
    vm.kernel_module_stop
    when '--help'
    vm.help
  else
    vm.help
  end  
end

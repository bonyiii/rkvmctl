require 'tmpdir'
require "rkvmctl"
require "test/unit"

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

class Class
  def publicize_methods
    saved_private_instance_methods = self.private_instance_methods
    self.class_eval { public *saved_private_instance_methods }
    yield
    self.class_eval { private *saved_private_instance_methods }
  end
end

#To not to print out usage message all the time during the tests...
#Create accessors for these instance variables
class RKvmctl
  attr_accessor :conf,:brctl,:kernel_module_running,:lsmod,:KERNEL_MODULE_NAME,:scriptname
=begin
  private
  def usage
    return nil
  end
=end
end


#The tests
class TestRKvmctl < Test::Unit::TestCase
  def test_private_methods_scope
    assert_raise(NoMethodError) {RKvmctl.new("").conf_load}
    #    assert(RKvmctl.private_method_defined?("bridge_check"))
    assert(RKvmctl.private_method_defined?("bridge_start"))
    assert(RKvmctl.private_method_defined?("env_check"))
    assert(RKvmctl.private_method_defined?("uid_check"))
    #    assert(RKvmctl.private_method_defined?("kernel_module_check"))
    assert(RKvmctl.private_method_defined?("kernel_module_start"))
  end
  
  def test_private_conf_load
    RKvmctl.publicize_methods do
      rkvmctl=RKvmctl.new("")
      #assert_nil(RKvmctl.new("").conf_load("nincs ilyen fájl"))
      assert_equal(false,rkvmctl.conf_load(nil))
      assert_equal(false,rkvmctl.conf_load("nincs ilyen fájl"))
      f=File.new(File.join(Dir.tmpdir,'gentoo_conf'),"w+")
      t=<<conf_file_content
host="gentoo"
id="12"
mem="1048"
noacpi=""
cpus="2"
mouse="tablet"
nic="e1000"
boot="c"
disktype0="ide"
media0="disk"
disk0="/media/hdd/lib/kvm/gentoo/gentoo2008_64_10G.qcow2"
disktype1=""
media1=""
disk1=""
disktype2="ide"
media2="cdrom"
disk2="/dev/dvd1"
disktype3=""
macaddress="DE:AD:BE:EF:28:97"
media3=""
disk3=""
script="/etc/qemu-ifup"
conf_file_content
      f.puts(t)
      f.readlines  #this is needed for some reason that i'm not aware of...
      assert(rkvmctl.conf_load(f.path))
      assert(rkvmctl.conf)
      assert_equal("gentoo",rkvmctl.conf["host"])
      assert_equal("12",rkvmctl.conf["id"])
      assert_equal("DE:AD:BE:EF:28:97",rkvmctl.conf["macaddress"])
      assert_equal("/media/hdd/lib/kvm/gentoo/gentoo2008_64_10G.qcow2",rkvmctl.conf["disk0"])
      assert_equal("/etc/qemu-ifup",rkvmctl.conf["script"])
      assert_nil(rkvmctl.conf["noacpi"])
      f.close
      File.delete(File.join(Dir.tmpdir,'gentoo_conf'))
      #       assert_raise(TypeError) {RKvmctl.new("").conf_load(nil)}
    end
  end
  
  def test_private_uid_check
    RKvmctl.publicize_methods do
      rkvmctl=RKvmctl.new("")
      rkvmctl.uid_check
      rkvmctl.uid_check
      assert_equal("/usr/bin/sudo /sbin/brctl",rkvmctl.brctl) unless Process.uid==0
      assert_equal("/sbin/brctl",rkvmctl.brctl) if Process.uid==0
    end
  end
  
  def test_private_kernel_module_load_unload
    RKvmctl.publicize_methods do
      rkvmctl=RKvmctl.new("")
      rkvmctl.uid_check
      ##TODO check CHECK something may be wrong with kernel loading...
      rkvmctl.kernel_module_start
      assert_equal(true,rkvmctl.env_check("#{rkvmctl.lsmod}","^#{rkvmctl.KERNEL_MODULE_NAME}.*"))
      rkvmctl.kernel_module_stop
      assert_equal(false,rkvmctl.env_check("#(rkvmctl.lsmod}","^#{rkvmctl.KERNEL_MODULE_NAME}.*"))
    end
  end
  
  def test_private_bridge_module_load_unload
    RKvmctl.publicize_methods do
      rkvmctl=RKvmctl.new("")
      rkvmctl.uid_check
      rkvmctl.bridge_start
      assert_equal(true,rkvmctl.env_check("#{rkvmctl.brctl} show",'br0.*'))
      rkvmctl.bridge_stop
      assert_equal(false,rkvmctl.env_check("#{rkvmctl.brctl} show",'br0.*'))
    end
  end
  
  def test_start_stop
    RKvmctl.publicize_methods do
      f=File.new(File.join(Dir.tmpdir,'gentoo_conf2'),"w+")
      t=<<conf_file_content
host="gentoo"
id="12"
mem="1048"
noacpi=""
cpus="2"
mouse="tablet"
nic="e1000"
boot="c"
disktype0="ide"
media0="disk"
hda="/media/hdd/lib/kvm/gentoo/gentoo2008_64_10G.qcow2"
disktype1=""
media1=""
disk1=""
disktype2="ide"
media2="cdrom"
disk2="/dev/dvd1"
disktype3=""
macaddress="DE:AD:BE:EF:28:97"
media3=""
disk3=""
script="/etc/qemu-ifup"
vnc_port="1"
daemonize="1"
conf_file_content
      f.puts(t)
      #      f.readlines  #this is needed for some reason that i'm not aware of...
      f.close
      rkvmctl=RKvmctl.new("")
      rkvmctl.start(File.join(Dir.tmpdir,'gentoo_conf2'))
      assert_equal(true,rkvmctl.env_check("#{PGREP} -lf kvm | #{GREP} -v #{rkvmctl.scriptname} | #{AWK} '\{ print $4 \}'",".*"))
      sleep 1
      rkvmctl.stop(File.join(Dir.tmpdir,'gentoo_conf2'))
      sleep 1
      assert_equal(false,rkvmctl.env_check("#{PGREP} -lf kvm | #{GREP} -v #{rkvmctl.scriptname} | #{AWK} '\{ print $4 \}'",".*"))
      File.delete(File.join(Dir.tmpdir,'gentoo_conf2'))
      rkvmctl.bridge_stop
      assert_equal(false,rkvmctl.env_check("#{rkvmctl.brctl} show",'br0.*'))
      rkvmctl.kernel_module_stop
      assert_equal(false,rkvmctl.env_check("#(rkvmctl.lsmod}","^#{rkvmctl.KERNEL_MODULE_NAME}.*"))
    end
  end
  
  #TODO test y,n,etc
  def test_vnc
    flunk
  end
  
  def test_status
    
  end
  
  def test_start_shutdown
    RKvmctl.publicize_methods do
      f=File.new(File.join(Dir.tmpdir,'gentoo_conf2'),"w+")
      t=<<conf_file_content
host="gentoo"
id="12"
mem="1048"
noacpi=""
cpus="2"
mouse="tablet"
nic="e1000"
boot="c"
disktype0="ide"
media0="disk"
hda="/media/hdd/lib/kvm/gentoo/gentoo2008_64_10G.qcow2"
disktype1=""
media1=""
disk1=""
disktype2="ide"
media2="cdrom"
disk2="/dev/dvd1"
disktype3=""
macaddress="DE:AD:BE:EF:28:97"
media3=""
disk3=""
script="/etc/qemu-ifup"
vnc_port="1"
daemonize="1"
conf_file_content
      f.puts(t)
      f.close
      rkvmctl=RKvmctl.new("")
      rkvmctl.start(File.join(Dir.tmpdir,'gentoo_conf2'))
      assert(File.exist?("/proc/#{rkvmctl.get_pid(File.join(Dir.tmpdir,'gentoo_conf2'))}"))
      rkvmctl.shutdown(File.join(Dir.tmpdir,'gentoo_conf2'))
      assert(File.exist?("/proc/#{rkvmctl.get_pid(File.join(Dir.tmpdir,'gentoo_conf2'))}"))
      sleep 5
      #Only passes if acpid is enabled whitin the virtual machine
      rkvmctl.shutdown(File.join(Dir.tmpdir,'gentoo_conf2'))
      assert_equal(false,File.exist?("/proc/#{rkvmctl.get_pid(File.join(Dir.tmpdir,'gentoo_conf2'))}"))
      File.delete(File.join(Dir.tmpdir,'gentoo_conf2'))
      rkvmctl.bridge_stop
    end
  end
end
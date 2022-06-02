extends Node

var PORT: int = 7373  # Port of server
var USER_PORT: int = 3737
var socketUDP: PacketPeerUDP
var listen: bool = false

func _ready():
	var output = []
	var host_ip: String = ''
	var subnet_mask: String = ''
	# Getting subnet mask + ip
# warning-ignore:unused_variable
	var result_code = OS.execute('ipconfig', [], true, output)
	for s in output:
		if not 'Subnet Mask' in s or not '  IPv4 Address' in s:
			continue
		subnet_mask = s.split('Subnet Mask')[1].split(': ')[1].split('\n')[0]
		host_ip = s.split('  IPv4 Address')[1].split(': ')[1].split('\n')[0]
		print('Host ip: ' + host_ip)
	
	# Setting up prefix (only if connectd + firewall is off):
	var prefix = get_prefix(host_ip, subnet_mask)
	
	socketUDP.listen(USER_PORT, host_ip)
	# Looking for a server - 
	socketUDP.set_broadcast_enabled(true)  # Enabling broadcasting
	socketUDP.set_dest_address('255.255.255.255', PORT)
	# Sending broadcast packet to discover. (3 times)
	for _i in range(3):
		socketUDP.put_packet('DISC#'.to_ascii())
	# Sending a request to individual incase broadcasting is disabled
	var ip_list = get_network_ips(prefix)
	for each in ip_list:
		socketUDP.set_dest_address(each, PORT)  # Changine address
		# Checking server
		for _i in range(3):
			socketUDP.put_packet('DISC#'.to_ascii())
	
	# Start Listening and creating ui for server choosing
	listen = true
	

func _physics_process(_delta):
	# Listening 
	if(listen and socketUDP.get_available_packet_count() > 0):
		var data = socketUDP.get_packet().get_string_from_ascii()
		data = data.split('#', true, 10)
		if data[0] == 'ACKN':
			# TODO - Create a HostOption node with proper name label.
			var ip = socketUDP.get_packet_ip()
			print('Found host! ', data[1])
	


# Get all IPS in a network that are viable of being a server.
func get_network_ips(prefix: String):
	# Gets all networks valid server ips (arping)
	var ip_lst = []
	var output = []
	OS.execute('arp', ['-a'], true, output)
	for section in output:
		section = section.split('\n')
		for line in section:
			if '  ' + prefix in line:
				var current_ip: String = line.split(' ')[2]
				ip_lst.append(current_ip)
	return ip_lst


# Get a prefix to rule out ips that doesn't fit being a server.
func get_prefix(ip: String, submask: String) -> String:
	var h_ip: Array = ip.split('.')
	var sub_mask: Array = submask.split('.')
	var cnt: int = 0  # While counter
	var prefix = ''  # result
	if ip != '127.0.0.1':  # Connection/Firewall check
		while cnt < h_ip.size():  # Going over each num
			if sub_mask[cnt] != '255':
				cnt += 1
				continue
			prefix += '.' + h_ip[cnt]
			cnt += 1
		prefix = prefix.substr(1)  # Getting rid of first dot.
	return prefix

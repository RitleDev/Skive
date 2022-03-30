extends Node

# Audio
var effect: AudioEffectCapture
var playback: AudioStreamPlaybackResampled = null
var recording
var is_recording = false


# Time varaibles
var timing: bool = false
var time = 0


# Peer for server/client
var socketUDP: PacketPeerUDP = PacketPeerUDP.new()
# Thread to run on.
var thread

var host_ip: String = '127.0.0.1'  # Machine own ip address
var subnet_mask: String = ''  # Used to get prefix
var prefix = ''  # Prefix of every ip in network

# Constants
# Port to host on - 
const SERVER_PORT: int = 7373
const CLIENT_PORT: int = 3737

const MAX_PLAYERS = 4


func _ready():
	var output = []
	# Getting subnet mask + ip
	OS.execute('ipconfig', [], true, output)
	for s in output:
		if not 'Subnet Mask' in s or not '  IPv4 Address' in s:
			continue
		subnet_mask = s.split('Subnet Mask')[1].split(': ')[1].split('\n')[0]
		host_ip = s.split('  IPv4 Address')[1].split(': ')[1].split('\n')[0]
		print('Host ip: ' + host_ip)
	
	# Setting up prefix (only if connectd + firewall is off):
	prefix = get_prefix(host_ip, subnet_mask)
	


# Responsible for hosting a server and managing connections
func server():
	print('Initializing server...')
	var status = socketUDP.listen(SERVER_PORT, host_ip)
	if status == 0:
		print('Server listen OK')
	while true:
		if socketUDP.get_available_packet_count() > 0:
			var array_bytes = socketUDP.get_packet()
			#print(array_bytes)
			var ip = socketUDP.get_packet_ip()
			var port = socketUDP.get_packet_port()
			print('From: <', ip, ', ', String(port), '>')
			var data = byte_array_to_string(array_bytes)
			#print(data)
			var response = server_protocol(data)
			socketUDP.set_dest_address(ip, port)
			socketUDP.put_packet(string_to_byte_array(response))


func client():
	print('Initializing client...')
	socketUDP.listen(CLIENT_PORT, host_ip)
	# Looking for a server - 
	socketUDP.set_broadcast_enabled(true)  # Enabling broadcasting
	socketUDP.set_dest_address('255.255.255.255', SERVER_PORT)
	# Sending broadcast packet to discover. (3 times)
	for i in range(3):
		socketUDP.put_packet(string_to_byte_array('DISC'))
	# Sending a request to individual incase broadcasting is disabled
	var ip_list = get_network_ips(prefix)
	for each in ip_list:
		socketUDP.set_dest_address(each, SERVER_PORT)  # Changine address
		# Checking server
		wait(0.05) # Delay between requests
		for i in range(3):
			socketUDP.put_packet(string_to_byte_array('DISC'))

	
	# Wating for an answer
	var done = false
	while not done:
		if socketUDP.get_available_packet_count() > 0:
			var array_bytes = socketUDP.get_packet()
			var ip = socketUDP.get_packet_ip()
			var port = socketUDP.get_packet_port()
			if byte_array_to_string(array_bytes) == 'ACKN':
				print('Server is: <', ip, ', ', String(port), '>')
				done = true


# Handle each client individually
func handle_client(ip: String, port: int, data):
	pass


func server_protocol(data):
	if data == 'DISC':  # Discover
		return 'ACKN'  # Acknowledge
	else: return null

# Starts a server on button click
func _on_ServerButton_pressed():
	thread = Thread.new()
	thread.start(self, 'server')
	var idx = AudioServer.get_bus_index("Record")
	effect = AudioServer.get_bus_effect(idx,1)
	# Setting playback stream
	playback = $AudioStreamPlayer.get_stream_playback()
	$AudioStreamPlayer.play()
	#effect.set_recording_active(true)
	is_recording = true
	
func _on_ClientButton_pressed():
	thread = Thread.new()
	thread.start(self, 'client')

# Converts an array of ints into a string. (using ASCII)
static func byte_array_to_string(array) -> String:
	var result: String = ''
	for item in array:
		result += char(item)
	return result

# Opposite of byte_array_to_string
func string_to_byte_array(string: String):
	var array = []
	for letter in string:
		array.append(ord(letter))
	return array


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
	

func wait(seconds: float):
	# Timer - uses _physics_proccess to count time and delay.
	time = 0
	timing = true
	while time <= seconds:
		pass
	timing = false
	time = 0
	
	
class User:
	func _init(name: String, position: Vector2, ip: String, port: int, 
	socketUDP: PacketPeerUDP):
		self.name = name
		self.position = position
		self.ip = ip
		self.port = port
		self.socketUDP = socketUDP

	# Data can be either String or TYPE_RAW_ARRAY(PoolByteArray)
	# See Docs: https://bit.ly/36c5nZ8 (For all types)
	func send_packet(data):
		if typeof(data) == 20:  # TYPE_RAW_ARRAY (PoolByteArray)
			self.socketUDP.set_dest_address(self.ip, self.port)
			self.socketUDP.put_packet(data)
		elif typeof(data) == 4:  # String
			self.socketUDP.set_dest_address(self.ip, self.port)
			self.socketUDP.put_packet(string_to_byte_array(data))
	
	# Opposite of byte_array_to_string
	static func string_to_byte_array(string: String):
		var array = []
		for letter in string:
			array.append(ord(letter))
		return array
		
		
func _physics_process(delta):
	# Time Counter
	if timing == true:
		time += delta


func _on_SendAudioTimer_timeout():
	if is_recording:
		var t = Thread.new()
		t.start(self, 'play_audio', recording)
		
		
func play_audio(data):
	#print(recording.size())
		recording = effect.get_buffer(effect.get_frames_available())
		print(recording.size())
		"""
		Converting example:
		print('1')
		var pb = PoolByteArray(Array(recording))
		print(PoolVector2Array(Array(pb)).size())
		print('2')"""
		#effect.clear_buffer()
		if recording.size() > 0:
			for frame in recording:
				playback.push_frame(frame)
	

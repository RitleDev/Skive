extends Node

# Audio
var effect: AudioEffectCapture
var playback: AudioStreamPlayback = null
var recording
var is_recording = false
var audio_id: int = 1  # Count audio messages sent TODO: make it not infinty
var current_sound: PoolVector2Array
var last_sound: PoolVector2Array


# Time varaibles
var timing: bool = false
var time = 0

# Client server loop booleans
var client_runnning: bool = false
var server_runnning: bool = false

# Selected server details (client protocol uses this)
var ser_ip = ''
var ser_port = null
var last_id = 0  # Prevent overrides of audio


# Peer for server/client
var socketUDP: PacketPeerUDP = PacketPeerUDP.new()
# Thread to run on.
var thread

var sound_thread

var users = {}  # Dict to hold all users/Key = IP(String): Value = User

var host_ip: String = '127.0.0.1'  # Machine own ip address
var subnet_mask: String = ''  # Used to get prefix
var prefix = ''  # Prefix of every ip in network

# Constants
# Port to host on - 
const SERVER_PORT: int = 7373
const CLIENT_PORT: int = 3737


func _ready():
	OS.low_processor_usage_mode = true  # Saving CPU usage and power.
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
	else:
		print('Server listen failed, error code: ', status)
	server_runnning = true


func client():
	print('Initializing client...')
	socketUDP.listen(CLIENT_PORT, host_ip)
	# Looking for a server - 
	socketUDP.set_broadcast_enabled(true)  # Enabling broadcasting
	socketUDP.set_dest_address('255.255.255.255', SERVER_PORT)
	# Sending broadcast packet to discover. (3 times)
	for i in range(3):
		socketUDP.put_packet(string_to_byte_array('DISC#'))
	# Sending a request to individual incase broadcasting is disabled
	var ip_list = get_network_ips(prefix)
	for each in ip_list:
		socketUDP.set_dest_address(each, SERVER_PORT)  # Changine address
		# Checking server
		for i in range(3):
			socketUDP.put_packet(string_to_byte_array('DISC#'))

	client_runnning = true  # Starting client loop


func client_protocol(args: Array):
	var data: PoolByteArray = args[0]
	var ip: String = args[1]
	var port: int = args[2]
	# Exiting if got a message from a different source
	if ip != ser_ip or port != ser_port:
		return
	
	# Refactoring data to match needs
	# Decompressing message and converting to string
	# Index when protocol stops being ascii and becomes binary
	var type_index = find_triple_hashtag(data)
	var splitted = data.subarray(0, type_index)
	splitted = byte_array_to_string(splitted).split('#')
	var msg_code = splitted[0]  # Getting message code
	var msg_id = int(splitted[1])  # Getting message ID (prevent override)
	var sound_length = int(splitted[2])
	var msg = data.subarray(type_index + 3, -1).decompress(sound_length, 3)
	#print('Code:', msg_code, ' ID:', msg_id, ' Length:', sound_length)
	
	if msg_id <= last_id:  # Ignoring message which already got handled
		return
	#print('Got ID> ' + String(msg_id))
	last_id = msg_id  # Setting new id
	if msg_code == 'SEND':
		#msg = parse_json(msg)
		#sound_thread = Thread.new()
		msg = parse_vector2(byte_array_to_string(msg))
		play_audio(msg)
		#sound_thread.start(self, 'play_audio', msg)
		current_sound = msg
		return
	


func server_protocol(data, ip, port):
	if data == 'DISC#':  # Discover
		if not users.has(ip):
			users[ip] = User.new('User', ip, port, socketUDP)
			#print(socketUDP)
		return 'ACKN#'  # Acknowledge
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
	playback = $AudioStreamPlayer.get_stream_playback()
	$AudioStreamPlayer.play()


# Converts an array of ints into a string. (using ASCII)
func byte_array_to_string(array: PoolByteArray) -> String:
	return array.get_string_from_ascii()  # TODO: Change program syntax.


# Opposite of byte_array_to_string
func string_to_byte_array(string: String):
	return string.to_ascii()


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


class User:
	var name
	var ip
	var port
	var socketUDP
	
	func _init(name: String, ip: String, port: int, 
	socketUDP: PacketPeerUDP):
		self.name = name
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
		else:
			self.socketUDP.set_dest_address(self.ip, self.port)
			self.socketUDP.put_packet(data)
	
	# Opposite of byte_array_to_string
	func string_to_byte_array(string: String):
		return string.to_ascii()  # TODO : Change program syntax.


func _on_SendAudioTimer_timeout():
	if is_recording:
		recording = effect.get_buffer(effect.get_frames_available())
		effect.clear_buffer()
		# Getting file ready to send in network. (using json & gzip)
		var js_rec = String(recording)
		# Message format looks like this:
		# SEND#AUDIO_ID#UNCOMPRESSED_LENGTH(string)###
		var to_send:PoolByteArray = string_to_byte_array('SEND#' + String(audio_id) + '#') \
		+	string_to_byte_array(String(string_to_byte_array(js_rec).size()) + '###') \
		+ 	string_to_byte_array(js_rec).compress(3)
		audio_id += 1
		#print('Sent> ' + String(to_send.size()) + ' ID > ' + String(audio_id))
		for user in users:
			users[user].send_packet(to_send)
		
		# Play only every 0.1 seconds
		#if current_sound != last_sound:
		#	var t = Thread.new()
		#	t.start(self, 'play_audio', current_sound)
		#last_sound = current_sound


func play_audio(recording):
	#effect.clear_buffer()
	#print(recording.size())
	if recording.size() > 0:
		for frame in recording:
			playback.push_frame(frame)
	#print('good')


func parse_vector2(data: String):
	data.erase(data.find("["),1)
	data.erase(data.find("]"),1)
	var s_data = data.split('),')
	var result: PoolVector2Array = []
	for cords in s_data:
		cords.erase(cords.find("("),1) # Erasing first bracket
		cords = cords.split(',')
		result.append(Vector2(float(cords[0]), float(cords[1])))
	return result


func find_triple_hashtag(data: PoolByteArray):
	var val = ord('#')
	var state = 0
	var cnt = 0
	for v in data:
		cnt += 1
		if v == val:
			state += 1
		else: state = 0  # reset
		if state == 3:
			return cnt - 3
	# If not found return -1
	return -1


# ------------------------------------------------------------
# here server and client listens to migrate preformance issues
# ------------------------------------------------------------
# <------->
# Client listen variables:
var done = false
var threads = []
var thread_counter: int = 0
# <------->
func _physics_process(delta):
	# Wating for an answer
	# communication with a single server
	if not done and client_runnning == true:
		if socketUDP.get_available_packet_count() > 0:
			var array_bytes = socketUDP.get_packet()
			var ip = socketUDP.get_packet_ip()
			var port = socketUDP.get_packet_port()
			if byte_array_to_string(array_bytes) == 'ACKN#' and ser_ip == '':
				print('Server is: <', ip, ', ', String(port), '>')
				ser_ip = ip
				ser_port = port
				#done = true
			else:
				#client_protocol(array_bytes, ip ,port)
				threads.append(Thread.new())
				threads[thread_counter].start(self, 'client_protocol', [array_bytes, ip, port])
				thread_counter += 1
	# Sever listen loop
	if server_runnning:
		if socketUDP.get_available_packet_count() > 0:
			var array_bytes = socketUDP.get_packet()
			#print(array_bytes)
			var ip = socketUDP.get_packet_ip()
			var port = socketUDP.get_packet_port()
			print('From: <', ip, ', ', String(port), '>')
			var data = byte_array_to_string(array_bytes)
			#print(data)
			var response = server_protocol(data, ip, port)
			socketUDP.set_dest_address(ip, port)
			var type: int = typeof(response)
			if type == 4:  # Converting to bytes if the message is string only
				response = string_to_byte_array(response)
			if type != 0:  # Checking if message isn't null
				socketUDP.put_packet(response)

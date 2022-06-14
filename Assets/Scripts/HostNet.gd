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

# Server loop booleans
var server_runnning: bool = false

# Selected server details (client protocol uses this)
var ser_ip = ''
var ser_port = null
var last_id = 0  # Prevent overrides of audio


# Peer for server/client
var socketUDP: PacketPeerUDP = PacketPeerUDP.new()
# Thread to run on.
var thread
var sound_locker: Mutex  # This is used to track msg ID and avoid confilct.
var create_locker: Mutex  # This is used when creating users and AudioStreams
var player_locker: Mutex  # This is used to prevent Audio collisions.
var user_id_counter: int  # This is used to give each user its own ID.

var sound_thread

var users = {}  # Dict to hold all users/Key = IP(String): Value = User

var id_users = {}  # Dict to hold all users id, audio ids (user_id:audio_id)

var host_ip: String = '127.0.0.1'  # Machine own ip address
var subnet_mask: String = ''  # Used to get prefix
var prefix = ''  # Prefix of every ip in network

# Constants
# Port to host on - 
const SERVER_PORT: int = 7373
const CLIENT_PORT: int = 3737


func _ready():
	sound_locker = Mutex.new()
	create_locker = Mutex.new()
	player_locker = Mutex.new()
	user_id_counter = 1  # Server is taking ID -> 0
	var output = []
	# Getting subnet mask + ip

	var result_code = OS.execute('ipconfig', [], true, output)
	for s in output:
		if not 'Subnet Mask' in s or not '  IPv4 Address' in s:
			continue
		subnet_mask = s.split('Subnet Mask')[1].split(': ')[1].split('\n')[0]
		host_ip = s.split('  IPv4 Address')[1].split(': ')[1].split('\n')[0]
		print('Host ip: ' + host_ip)
	
	# Setting up prefix (only if connectd + firewall is off):
	prefix = get_prefix(host_ip, subnet_mask)
	Server_init()
	$RichTextLabel.bbcode_text = '[center]Hosting on ' + host_ip + '[/center]'


# Responsible for hosting a server and managing connections
func server():
	print('Initializing server...')
	var status = socketUDP.listen(SERVER_PORT, '*') # host_ip
	if status == 0:
		print('Server listen OK')
	else:
		print('Server listen failed, error code: ', status)
		return
	server_runnning = true


func server_protocol(data, ip, port):
	# Processing message: 
	var type_index = find_triple_hashtag(data)
	var splitted = data.subarray(0, type_index)
	splitted = splitted.get_string_from_ascii().split('#')
	var code = splitted[0]
	
	# Handeling message
	if code == 'DISC':  # Discover
		if not users.has(ip):
			create_locker.lock()  # Locking to prevent data collision
			users[ip] = User.new('User', ip, port, socketUDP, user_id_counter)
			print('new user> ', ip, ', ', String(port))
			user_id_counter += 1
			create_locker.unlock()
			#print(socketUDP)
		return 'ACKN#'.to_ascii()  # Acknowledge
	
	# Playing audio if recieved from a certain user, must be verified
	elif code == 'SEND':
		if not users.has(ip):
			return 'FAIL#'.to_ascii()  # No auth
		create_locker.lock()  # Locking when creating a StreamPlayer
		# Godot doesnt support dots in scene node name
		var ip_no_dots: String = ip.split('.').join('')
		var node: AudioStreamPlayer = get_node_or_null(ip_no_dots)  # Finding Audio
		if node == null:
			node = AudioStreamPlayer.new()
			node.stream = AudioStreamGenerator.new()
			node.stream.buffer_length = 0.1
			add_child(node)
			node.name = ip_no_dots
			node.play()
		create_locker.unlock()
		var pb = node.get_stream_playback()
		var msg_id = int(splitted[1])  # Getting message ID (prevent override)
		var sound_length = int(splitted[2])
		var sound = data.subarray(type_index + 3, -1).decompress(sound_length, 3)
		if users[ip].audio_id < msg_id:
			sound_locker.lock()  # Thread lock to avoid confilct
			users[ip].audio_id = msg_id
			sound_locker.unlock()
			# TODO - play with threads.
			if sound.size() > 5:
				play_audio(parse_vector2(sound.get_string_from_ascii()), pb)
			# After playing sending to all other clients:
			# Creating the new message
			var sending = ('SEND#' + String(msg_id) + '#' \
			+ String(sound_length) + '#' + String(users[ip].id) \
			+ '###').to_ascii()
			# Appeniding unziped audio
			sending.append_array(data.subarray(type_index + 3, -1))
			# Redirecting data to all users
			for user in users:
				if users[user].id != users[ip].id:
					for _i in range(3):
						socketUDP.put_packet(sending)
		
			
	else: return null


# Starts a server on button click
func Server_init():
	thread = Thread.new()
	thread.start(self, 'server')
	var idx = AudioServer.get_bus_index("Record")
	effect = AudioServer.get_bus_effect(idx,1)
	# Setting playback stream
	playback = $AudioStreamPlayer.get_stream_playback()
	$AudioStreamPlayer.play()
	#effect.set_recording_active(true)
	is_recording = true


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
	var name: String  # Client name
	var ip: String  # Client ip
	var port: int  # Client port
	var id: int  # Client identification number
	var socketUDP: PacketPeerUDP  # Socket to communicate (belongs to server)
	var audio_id: int  # Last audio identification number incoming.
	
	func _init(name: String, ip: String, port: int, 
	socketUDP: PacketPeerUDP, id: int):
		self.name = name
		self.ip = ip
		self.port = port
		self.socketUDP = socketUDP
		self.audio_id = 0  # First incoming ID is 1
		self.id = id

	# Data can be either String or TYPE_RAW_ARRAY(PoolByteArray)
	# See Docs: https://bit.ly/36c5nZ8 (For all types)
	func send_packet(data):
		if typeof(data) == 20:  # TYPE_RAW_ARRAY (PoolByteArray)
			self.socketUDP.set_dest_address(self.ip, self.port)
			self.socketUDP.put_packet(data)
		elif typeof(data) == 4:  # String
			self.socketUDP.set_dest_address(self.ip, self.port)
			self.socketUDP.put_packet(data.to_ascii())
		else:
			self.socketUDP.set_dest_address(self.ip, self.port)
			self.socketUDP.put_packet(data)


func _on_SendAudioTimer_timeout():
	if is_recording and server_runnning:
		recording = effect.get_buffer(effect.get_frames_available())
		effect.clear_buffer()
		# Getting file ready to send in network. (using json & gzip)
		var js_rec = String(recording)
		# Message format looks like this('0' is the id of the server):
		# SEND#AUDIO_ID#UNCOMPRESSED_LENGTH(string)#SERVER_USER_ID###audio
		var to_send:PoolByteArray = ('SEND#' + String(audio_id) + '#').to_ascii() \
		+ (String(js_rec.to_ascii().size()) + '#0###').to_ascii() \
		+ js_rec.to_ascii().compress(3)
		audio_id += 1
		#print('Sent> ' + String(to_send.size()) + ' ID > ' + String(audio_id))
		# Sending data to all users
		for user in users:
			users[user].send_packet(to_send)
		
		# Play only every 0.1 seconds
		#if current_sound != last_sound:
		#	var t = Thread.new()
		#	t.start(self, 'play_audio', current_sound)
		#last_sound = current_sound


func play_audio(recording, playback):
	#effect.clear_buffer()
	#print(recording.size())
	if recording != null and recording.size() > 0:
		player_locker.lock()
		for frame in recording:
			playback.push_frame(frame)
		player_locker.unlock()
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
	var val = 35  # ord('#')
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
# here server listens to migrate performance issues
# ------------------------------------------------------------
# <------->
# Client listen variables:
var done = false
var threads = []
var thread_counter: int = 0
# <------->
func _physics_process(_delta):
	# Sever listen loop
	if server_runnning:
		while socketUDP.get_available_packet_count() > 0:
			var array_bytes = socketUDP.get_packet()
			#print(array_bytes)
			var ip = socketUDP.get_packet_ip()
			var port = socketUDP.get_packet_port()
			#print('From: <', ip, ', ', String(port), '>')
			var response = server_protocol(array_bytes, ip, port)
			socketUDP.set_dest_address(ip, port)
			var type: int = typeof(response)
			if type == 4:  # Converting to bytes if the message is string only
				response = response.to_ascii()
			if response != null:
				socketUDP.put_packet(response)

# Waits for threads to finish and destroys them
# See at this forum to understand how it works:
# https://godotengine.org/qa/33120/how-do-thread-and-wait_to_finish-work
func end_of_thread(id: int):
	threads[id].wait_to_finish()
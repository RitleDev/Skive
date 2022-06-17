extends Node

# Audio
var effect: AudioEffectCapture
var playback: AudioStreamPlayback = null
var recording
var is_recording = false
var audio_id: int = 1  # Count audio messages sent TODO: make it not infinty
var current_sound: PoolVector2Array
var last_sound: PoolVector2Array


# Encryption
var IV: PoolByteArray = [12, 254, 26, 95, 2, 17, 45, 127, \
	+ 58, 192, 11, 64, 83, 56, 24, 55]


# Time varaibles
var timing: bool = false
var time = 0

# Server loop booleans & Availability states
var server_runnning: bool = false
var open: bool = true

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
var text_locker: Mutex
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
	text_locker = Mutex.new()
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
		add_line('Hosting on: ' + host_ip)
	
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
		add_line('Server Started!')
	else:
		print('Server listen failed, error code: ', status)
		add_line('Server faild to start.')
		return
	server_runnning = true


func server_protocol(data, ip, port):
	# Processing message: 
	var type_index = find_triple_hashtag(data)
	var splitted = data.subarray(0, type_index)
	splitted = splitted.get_string_from_ascii().split('#',false, 20)
	var code = splitted[0]
	
	# Handeling message
	if code == 'DISC' and open:  # Discover
		return 'ACKN#'.to_ascii()  # Acknowledge discovery

	elif code == 'JOIN' and open and splitted[1] != '':
		for user in users:  # Checking if user already exists
			if user == ip:
				return
		var key: CryptoKey = CryptoKey.new()
		var crypto: Crypto = Crypto.new()
		key.load_from_string(splitted[1], true)
		var aes_key = AES.generate_key()
		var ret = 'PLAY###'.to_ascii()
		ret.append_array(crypto.encrypt(key, aes_key))
		create_locker.lock()  # Locking to prevent data collision
		if not users.has(ip):
			users[ip] = User.new('User', ip, port, socketUDP, user_id_counter, 
			aes_key)
			print('new user> ', ip, ', ', String(port))
			add_line('User: ' + ip + ' Connected.')
			user_id_counter += 1
		create_locker.unlock()
		return ret
		
		
	elif (code == 'JOIN' or code == 'DISC') and not open:
		return 'FAIL#1'.to_ascii()  # Server is closed to joining users.
	
	elif code == 'JOIN' and open and splitted[1] == '':
		return 'FAIL#2'.to_ascii()  # No key given

	# Playing audio if recieved from a certain user, must be verified
	elif code == 'SEND':
		if not users.has(ip):
			return 'FAIL#3'.to_ascii()  # No auth
		create_locker.lock()  # Locking when creating a StreamPlayer
		# Godot doesnt support dots in scene node name
		var ip_no_dots: String = ip.split('.').join('')
		users[ip].active = true
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
		var sound = AES.decrypt_CBC(data.subarray(type_index + 3, -1), 
			users[ip].key, IV)
		var sound_to_send = sound  # Later sending that to the other clients
		sound = sound.decompress(sound_length, 3)
		if users[ip].audio_id < msg_id:
			sound_locker.lock()  # Thread lock to avoid confilct
			users[ip].audio_id = msg_id
			sound_locker.unlock()
			if sound.size() > 5:  # Checking audio isn't completely empty.
				play_audio(parse_vector2(sound.get_string_from_ascii()), pb)
			# After playing sending to all other clients:
			# Creating the new message
			var sending = ('SEND#' + String(msg_id) + '#' \
			+ String(sound_length) + '#' + String(users[ip].id) \
			+ '###').to_ascii()
			# Appending unziped audio
			#sending.append_array(data.subarray(type_index + 3, -1))
			# Redirecting data to all users
			for user in users:
				if users[user].id != users[ip].id:  # Prevet echo of audio
					var final_send = []
					final_send.append_array(sending)
					final_send.append_array(AES.encrypt_CBC(sound_to_send,
					users[user].key, IV))
					for _i in range(3):
						users[user].send_packet(final_send)
		return ''.to_ascii()
	elif code == 'EXIT' and users.has(ip):  # user disconnection
		add_line('User: ' + ip + ' disconnected.')
		create_locker.lock()
		users.erase(ip)
		create_locker.unlock()


	else: return 'FAIL#0'.to_ascii()


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
	var key: PoolByteArray  # AES Key saving per user.
	var active: bool  # Checks whether the user has disconnected without notice.
	
	func _init(name: String, ip: String, port: int, 
	socketUDP: PacketPeerUDP, id: int, key: PoolByteArray):
		self.name = name
		self.ip = ip
		self.port = port
		self.socketUDP = socketUDP
		self.audio_id = 0  # First incoming ID is 1
		self.id = id
		self.key = key
		self.active = true  # Giving the user first 5 seconds spair to not

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
		var packet:PoolByteArray = ('SEND#' + String(audio_id) + '#').to_ascii() \
		+ (String(js_rec.to_ascii().size()) + '#0###').to_ascii()
		audio_id += 1
		#print('Sent> ' + String(to_send.size()) + ' ID > ' + String(audio_id))
		# Sending data to all users
		for user in users:
			var final_packet = []
			final_packet.append_array(packet)
			final_packet.append_array(
				AES.encrypt_CBC(js_rec.to_ascii().compress(3), users[user].key,
				IV))
			for _i in range(3):
				users[user].send_packet(final_packet)
		
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


func _on_StatusButton_pressed():
	var node: Button = $StatusButton
	if open:
		open = false
		node.text = 'CLOSED'
		node.add_color_override("font_color", Color('#e3092a'))
		node.add_color_override("font_color_focus", Color('#e3092a'))
	else:
		open = true
		node.text = 'OPEN'
		node.add_color_override("font_color", Color("#3cef0a"))
		node.add_color_override("font_color_focus", Color("#3cef0a"))


# Kick users that are timed out.
func _on_ActivityTimer_timeout():
	for user in users:
		if users[user].active:
			users[user].active = false  # reset check for later.
		else:
			create_locker.lock()
			users.erase(user)
			create_locker.unlock()
			print('User: ', user, ' timed out.')
			add_line('User: ' + user + ' timed out.')


# Letting all clients know that the server is shutting down.
func on_Back_pressed():
	is_recording = false
	server_runnning = false
	for user in users:
		for _i in range(3):
			users[user].send_packet('SHUT#DOWN'.to_ascii())


func add_line(text: String):
	text_locker.lock()
	$Console.text +=  text + '\n'
	var current_line = $Console.get_line_count()
	if current_line > 7:  # Erasing the top line.
		var txt = $Console.text.split('\n')
		$Console.text = $Console.text.substr(txt[0].length() + 1, -1)
	#$Console.scroll_vertical = current_line
	text_locker.unlock()
	

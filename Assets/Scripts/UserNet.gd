extends Node

# This is the client's script.

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

# Selected server details (client protocol uses this)
export var ser_ip = ''
var ser_port = 7373
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

# Setup vars
onready var is_all_set: bool = false

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
# warning-ignore:unused_variable
	var result_code = OS.execute('ipconfig', [], true, output)
	for s in output:
		if not 'Subnet Mask' in s or not '  IPv4 Address' in s:
			continue
		subnet_mask = s.split('Subnet Mask')[1].split(': ')[1].split('\n')[0]
		host_ip = s.split('  IPv4 Address')[1].split(': ')[1].split('\n')[0]
		print('Host ip: ' + host_ip)
	
	# Starting client
	thread = Thread.new()
	thread.start(self, 'client')


func client():
	print_debug('Initializing client...')
	socketUDP.listen(CLIENT_PORT, host_ip)
	
	
	var idx = AudioServer.get_bus_index("Record")
	effect = AudioServer.get_bus_effect(idx,1)
	playback = $AudioStreamPlayer.get_stream_playback()
	$AudioStreamPlayer.play()
	
	
	client_runnning = true  # Starting client loop
	is_recording = true


func client_protocol(args: Array):
	var data: PoolByteArray = args[0]
	var ip: String = args[1]
	var port: int = args[2]
	var thread_id:int = args[3]
	call_deferred('end_of_thread', thread_id)
	#print('server detailes: ', ser_ip, ', ', port)
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
	#print('Code:', msg_code, ' ID:', msg_id, ' Length:', sound_length)
	
	if msg_code == 'SEND':
		var msg_id = int(splitted[1])  # Getting message ID (prevent override)
		var sound_length = int(splitted[2])
		var user_id = int(splitted[3])
		var msg = data.subarray(type_index + 3, -1).decompress(sound_length, 3)
		# If no such user exist create new Audio Stream
		create_locker.lock()
		if not user_id in id_users:
			var node = AudioStreamPlayer.new()
			node.stream = AudioStreamGenerator.new()
			node.stream.buffer_length = 0.1
			node.name = String(user_id)
			add_child(node)
			node.play()
			id_users[user_id] = 0
		create_locker.unlock()
		var node: AudioStreamPlayer = get_node_or_null(String(user_id))
		var pb = node.get_stream_playback()
		# If message id is smaller than the last id dont play the audio
		if msg_id <= id_users[user_id]:
			return
		
		sound_locker.lock()  # Thread lock to avoid confilct
		id_users[user_id] = msg_id
		sound_locker.unlock()
		play_audio(parse_vector2(msg.get_string_from_ascii()), pb)
		return


# Converts an array of ints into a string. (using ASCII)
func byte_array_to_string(array: PoolByteArray) -> String:
	return array.get_string_from_ascii()  # TODO: Change program syntax.


# Opposite of byte_array_to_string
func string_to_byte_array(string: String):
	return string.to_ascii()


func _on_SendAudioTimer_timeout():
	if is_recording and client_runnning and ser_ip != '':
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
		for i in range(3):
			socketUDP.put_packet(to_send)


func play_audio(recording, playback):
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
# here client listens to migrate performance issues
# ------------------------------------------------------------
# <------->
# Client listen variables:
var done = false
var threads = []
var thread_counter: int = 0
# <------->
func _physics_process(_delta):
	# Waiting for an ip from Discover.gd
	if !is_all_set:
		if ser_ip != '':
			is_all_set = true
			socketUDP.set_dest_address(ser_ip, ser_port)
	# communication with a single server
	if not done and client_runnning == true:
		if socketUDP.get_available_packet_count() > 0:
			var array_bytes = socketUDP.get_packet()
			var ip = socketUDP.get_packet_ip()
			var port = socketUDP.get_packet_port()
			if ser_ip == ip and ser_port == port:
				#client_protocol(array_bytes, ip ,port)
				array_bytes.get_string_from_ascii()
				#client_protocol([array_bytes, ip, port])
				threads.append(Thread.new())
				threads[thread_counter].start(self, 'client_protocol', [array_bytes, ip, port, thread_counter])
				thread_counter += 1

# Waits for threads to finish and destroys them
# See at this forum to understand how it works:
# https://godotengine.org/qa/33120/how-do-thread-and-wait_to_finish-work
func end_of_thread(id: int):
	threads[id].wait_to_finish()


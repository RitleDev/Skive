extends Node

# Peer for server/client
var socketUDP: PacketPeerUDP = PacketPeerUDP.new()
# Thread to run on.
var thread

var host_ip: String = '127.0.0.1'

# Constants
# Port to host on - 
const SERVER_PORT: int = 7373
const CLIENT_PORT: int = 3737

const MAX_PLAYERS = 4


func _ready():
	host_ip = get_local_ip()


# Responsible for hosting a server and managing connections
func server():
	print('Initializing server...')
	var status = socketUDP.listen(SERVER_PORT, host_ip)
	if status == 0:
		print('Server listen OK')
	while true:
		if socketUDP.get_available_packet_count() > 0:
			var array_bytes = socketUDP.get_packet()
			print(array_bytes)
			var ip = socketUDP.get_packet_ip()
			var port = socketUDP.get_packet_port()
			print('From: <', ip, ', ', String(port), '>')
			var data = byte_array_to_string(array_bytes)
			print(data)
			var response = server_protocol(data)
			socketUDP.set_dest_address(ip, port)
			socketUDP.put_packet(string_to_byte_array(response))


func client():
	print('Initializing client...')
	socketUDP.listen(CLIENT_PORT, host_ip)
	socketUDP.set_broadcast_enabled(true)  # Enabling broadcasting
	socketUDP.set_dest_address('255.255.255.255', SERVER_PORT)
	# Sending broadcast packet to discover. (3 times)
	for i in range(3):
		socketUDP.put_packet(string_to_byte_array('DISC'))
	var done = false
	# Wating for an answer
	while not done:
		if socketUDP.get_available_packet_count() > 0:
			var array_bytes = socketUDP.get_packet()
			var ip = socketUDP.get_packet_ip()
			var port = socketUDP.get_packet_port()
			if byte_array_to_string(array_bytes) == 'ACKN':
				print('Server is: <', ip, ', ', String(port), '>')
				done = true


# Handle each client individually
func handle_client(ip: String, port: int):
	pass


func server_protocol(data):
	if data == 'DISC':  # Discover
		return 'ACKN'  # Acknowledge
	else: return null

# Starts a server on button click
func _on_ServerButton_pressed():
	thread = Thread.new()
	thread.start(self, 'server')
	
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
	
func get_local_ip() -> String:
	var ip
	for address in IP.get_local_addresses():
		if (address.split('.').size() == 4) and address.split('.')[0] != '127':
			ip=address
	return ip
	
	
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




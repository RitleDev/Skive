class_name AES  # 128 bit

# This class manages AES encryption with static functions for ease of use.
# Has convenient padding and unpadding with simple key generation.
# Created by Ritle.
# Github - https://github.com/RitleHub


# Adds padding because AES only works in chunks of 128 or 256 bits.
static func pad(data: PoolByteArray) -> PoolByteArray:
	# Offset of last 16 bytes
	var length = data.size() % 16
	# Padding to add to the data.
	var padding = range((16-length) + 16) # Creating array at desired size.
	# Setting value to the length of the offset to later unpad
	for val in padding:
		val = length
	data.append_array(padding) # Adding the padding
	return data


# Removes the padding to view the original message.
static func unpad(data: PoolByteArray) -> PoolByteArray:
	# Getting offset of the last 16 bytes
	var length = data[-1]
	# Returing a sub array, 
	# removing first 32(16 * 2) bytes then adding the offset bytes
	return data.subarray(0, data.size() - 32 + length)
	
	
# generates random a 16 byte key size.
static func generate_key() -> PoolByteArray: 
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var key: PoolByteArray = []
	for _i in range(16):
		key.append(rng.randi_range(0, 255))  # Generating a byte.
	return key

# Same as generate_key(), just with a diffrent name.
# This is for better code understanding.
static func generate_iv() -> PoolByteArray:
	return generate_key()

# Encrypt 128 bit cbc mode with padding.
# All variables need to be recieved as PoolByteArray
# Tip - Use to_utf8() or to_ascii() for text
static func encrypt_CBC(data: PoolByteArray, key: PoolByteArray,
 iv: PoolByteArray) -> PoolByteArray:
	var aes = AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, key, iv)
	var encrypted = aes.update(pad(data))
	aes.finish()
	return encrypted

# Decrypts a 128 bit AES cbc mode cipher
# All variables need to be recieved as PoolByteArray.
# Tip - Use to_utf8() or to_ascii() for text
static func decrypt_CBC(data: PoolByteArray, key: PoolByteArray,
 iv: PoolByteArray) -> PoolByteArray:
	var aes = AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, key, iv)
	var decrypted = unpad(aes.update(data))
	aes.finish()
	return decrypted

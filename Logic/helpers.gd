static func generate_uuid_v4() -> String:
	var crypto = Crypto.new()
	# Generate 16 random bytes
	var bytes = crypto.generate_random_bytes(16)
	
	# Set the version (4) and variant (RFC 4122)
	# 0x40 at index 6, 0x80 at index 8
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	
	var hex = bytes.hex_encode()
	
	# Format: 8-4-4-4-12
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12)
	]

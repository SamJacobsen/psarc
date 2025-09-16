module psarc;

import squiz_box;

import std.stdio;
import std.array;
import std.range;
import std.file;
import std.format;
import std.bitmanip;
import std.string;
import std.digest.md;
import std.file : write;
import std.string : splitLines;
import std.exception : enforce;

enum ArchiveFlags {
	relative = 0,
	ignorecase = 1,
	absolute = 2
}

struct TocEntry {
	ubyte[16] nameDigestMD5;
	uint blockIndex;
	ulong uncompressedSize : 40;
	ulong fileOffset : 40;

	this(ref ubyte[] buffer) {
		this.nameDigestMD5 = buffer[0 .. 16];
		buffer = buffer[16 .. $];
		this.blockIndex = buffer.read!uint();
		this.uncompressedSize = read5BUlong(buffer);
		this.fileOffset = read5BUlong(buffer);
	}
}

struct PSARC {
	const static string signature = "PSAR";
	uint tocLength;
	uint tocEntrySize;
	uint tocEntryCount;
	uint blockSize;
	uint flags;
	TocEntry[] entries;
	ushort[] zLength;
	string[] names;

	SquizAlgo algo;

	this(ref ubyte[] buffer) {
		char[4] magic = cast(char[4]) buffer[0 .. 4];
		buffer = buffer[4 .. $];

		enforce(this.signature == magic,
			format("Unexpected file type: signature %s does not match %s", magic, this.signature));

		ushort major = buffer.read!ushort();
		ushort minor = buffer.read!ushort();
		char[4] compressionType = cast(char[4]) buffer[0 .. 4];
		buffer = buffer[4 .. $];

		switch (compressionType) {
			case "zlib":
				this.algo = Inflate.init.squizAlgo;
				break;
			case "lzma":
				auto l = DecompressLzma.init;
				l.format = LzmaFormat.legacy;
				this.algo = l.squizAlgo;
				break;
			default:
				throw new Exception(format("Unsupported compression algo %s", compressionType));
		}

		this.tocLength = buffer.read!uint();
		this.tocEntrySize = buffer.read!uint();
		this.tocEntryCount = buffer.read!uint();
		this.blockSize = buffer.read!uint();
		this.flags = buffer.read!uint();

		this.entries = new TocEntry[tocEntryCount];
		for (uint i; i < tocEntryCount; i++) {
			this.entries[i] = TocEntry(buffer);
		}

		uint tocLen = 32 + (tocEntrySize * tocEntryCount);
		uint blockLen = (this.tocLength - tocLen) / 2;
		this.zLength = new ushort[blockLen];
		for (uint i; i < blockLen; i++) {
			this.zLength[i] = buffer.read!ushort();
		}

		this.names = std.string.splitLines(cast(string) this.readEntry(buffer, 0));
	}

	ubyte[] readEntry(ref ubyte[] buffer, uint index) {
		enforce(index < this.entries.length, "Index out of range");

		TocEntry entry = this.entries[index];
		size_t offset = entry.fileOffset - this.tocLength;

		ulong writePos;
		uint zIndex = entry.blockIndex;
		ubyte[] dataBuilder = new ubyte[entry.uncompressedSize];

		while (writePos < entry.uncompressedSize) {
			const(ubyte)[] data;
			if (this.zLength[zIndex] == 0) {
				data = buffer[offset .. this.blockSize + offset];
				offset += this.blockSize;
			} else if (this.zLength[zIndex] == entry.uncompressedSize - writePos) {
				data = buffer[offset .. entry.uncompressedSize - writePos + offset];
				offset += entry.uncompressedSize - writePos;
			} else {
				ubyte[] compressedData = buffer[offset .. this.zLength[zIndex] + offset];
				data = only(compressedData).squiz(this.algo).join();
				offset += this.zLength[zIndex];
			}

			dataBuilder[writePos .. writePos + data.length] = data;
			writePos += data.length;
			zIndex++;
		}

		return dataBuilder;
	}
}

ulong read5BUlong(ref ubyte[] buffer) {
	ulong result =
		(cast(ulong) buffer[0] << 32) |
		(cast(ulong) buffer[1] << 24) |
		(cast(ulong) buffer[2] << 16) |
		(cast(ulong) buffer[3] << 8) |
		(cast(ulong) buffer[4]);

	buffer = buffer[5 .. $];
	return result;
}

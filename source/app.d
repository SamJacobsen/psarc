import std.getopt;
import std.stdio;
import std.file;
import std.path;
import psarc : PSARC, ArchiveFlags;
import std.uni : toLower;
import std.exception : enforce;
import std.digest.md : md5Of;

void main(string[] args) {
	string inpt;
	getopt(args,
		std.getopt.config.required,
		"file|f", "Input file", &inpt);

	enforce(toLower(extension(inpt)) == ".psarc", "Unexpected extension " ~ extension(inpt));

	ubyte[] buffer = cast(ubyte[]) read(inpt);
	PSARC arc = PSARC(buffer);

	string arcName = baseName(stripExtension(inpt));

	for (int i = 1; i < arc.tocEntryCount; i++) {
		enforce(md5Of(arc.names[i - 1]) == arc.entries[i].nameDigestMD5, "MD5 mismatch");
		string path = arc.names[i - 1];
		if(arc.flags & ArchiveFlags.relative) {
		} 
		
		if(arc.flags & ArchiveFlags.ignorecase) {
			path = path.toLower();
			arcName = arcName.toLower();
		} 
		
		if(arc.flags & ArchiveFlags.absolute) {
			path = path[1..$];
		}

		path = buildPath(arcName, path);
		
		if (!exists(dirName(path))) {
			mkdirRecurse(dirName(path));
		}
		std.file.write(path, arc.readEntry(buffer, i));
	}
}

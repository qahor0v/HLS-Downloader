/// imported packages

/// Bu yerda yuklab oligan audio va video stream (m3u8) fayllaridan yangi local hls (m3u8) hosil qilinadi

abstract class HlsSaverToStorage {
  Future<String?> saveFile(DownloadedToSave movie);
}

class HlsSaver implements HlsSaverToStorage {
  final Ref ref;

  HlsSaver(this.ref);

  @override
  Future<String?> saveFile(DownloadedToSave movie) async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final saveDir = Directory(
      p.join(
        appDocDir.path,
        Uri.parse(movie.url).hashCode.toString(),
      ),
    );
    if (!await saveDir.exists()) {
      await saveDir.create();
    }
    final filepath = p.join(saveDir.path, "master.m3u8");
    var file = File(filepath);



/// Bu yerda hls fayli formati ko'rsatilgan.
    final m3u8 = """#EXTM3U
    
#EXT-X-STREAM-INF:BANDWIDTH=${movie.bandWidth},CODECS="${movie.codecVideo}",AUDIO="stereo",RESOLUTION=426x240
${movie.video}


#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="stereo",LANGUAGE="${movie.lang}",NAME="${movie.langName}",CODECS="${movie.codecAudio}",DEFAULT=YES,URI="${movie.audio}\"""";

    file.writeAsStringSync(
      m3u8,
    );
    log("Completed: $m3u8");

    return file.path;
  }
}
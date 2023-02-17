/// imported packages

abstract class DownloadFromBackend {
  String getFilePath(String url);

  List<String> pathSegments(String url);

  Future<File> downloadFile(String url, String filepath, String filename,
      Map<String, String> headers);

  Future<List<Segment>> getHlsMediaFiles(Uri uri, List<String> lines);

  Future<DownloadContent> loadFileMetadata(String url, headers);

  Future<String> load(String url, Map<String, String> headers,
      Function(double) progress, bool cancel);
}

class DownloadManagerBackend implements DownloadFromBackend {
  @override
  Future<File> downloadFile(String url, String filepath, String filename,
      Map<String, String> headers) async {
    final dio = Dio();
    final response = await dio.get(
      url,
      options: Options(
        headers: headers,
        responseType: ResponseType.bytes,
      ),
    );
    final bytes = response.data;
    final file = File('$filepath/$filename');

    for (final f in pathSegments(filename)) {
      final d = Directory(p.join(filepath, f));
      if (!await d.exists()) {
        await d.create();
      }
    }

    if (!await file.exists()) {
      await file.create();
    }

    await file.writeAsBytes(bytes);
    return file;
  }

  @override
  String getFilePath(String url) {
    final uri = Uri.parse(url);

    return uri.pathSegments.last;
  }

  @override
  Future<List<Segment>> getHlsMediaFiles(Uri uri, List<String> lines) async {
    HlsPlaylist? playList;

    try {
      playList = await HlsPlaylistParser.create().parse(uri, lines);
    } on ParserException catch (e) {
      log('HLS Parsing Error: $e');
    }

    if (playList is HlsMediaPlaylist) {
      log('MEDIA Playlist');
      return playList.segments;
    } else {
      return [];
    }
  }

  @override
  Future<String> load(String url, Map<String, String> headers,
      Function(double) progress, bool cancel) async {
    final filename = getFilePath(url);
    final appDocDir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory(p.join(
      appDocDir.path,
      url.hashCode.toString(),
    ));
    if (!await downloadDir.exists()) {
      await downloadDir.create();
    }
    final filepath = p.join(downloadDir.path, filename);
    var file = File(filepath);
    if (!await file.exists()) {
      file = await downloadFile(url, downloadDir.path, filename, headers);
    }
    final lines = await file.readAsLines();
    final mediaSegments = await getHlsMediaFiles(Uri.parse(file.path), lines);
    final total = mediaSegments.length;
    var currentProgress = 0.0;
    for (final entry in mediaSegments.asMap().entries) {
      log("Downloaded: $cancel");
      if (cancel) {
        log('Cancelled!');
        break;
      }
      final index = entry.key;
      final seg = entry.value;
      final urlToDownload = p.join(
        pathSegments(url).join('/'),
        seg.url,
      );
      var ff = File(p.join(downloadDir.path, seg.url));
      if (!await ff.exists()) {
        await downloadFile(urlToDownload, downloadDir.path, seg.url!, headers);
      }
      if (index != total - 1) {
        currentProgress += (1 / total) * 100;
        await progress(currentProgress);
        //  log("\n=====$type:  $currentProgress % ======================");
      } else {
        currentProgress = 100.0;
        await progress(currentProgress);
      }
    }

    return file.absolute.path;
  }

  @override
  Future<DownloadContent> loadFileMetadata(String url, headers) async {
    final uri = Uri.parse(url);
    final client = http.Client();
    final req = await client.get(Uri.parse(url), headers: headers);
    log("${req.statusCode}");
    final lines = req.body;
    HlsPlaylist? playList;
    try {
      playList = await HlsPlaylistParser.create().parseString(uri, lines);
    } catch (error) {
      log("HlsPlaylistParser Error:P $error");
    }
    if (playList is HlsMediaPlaylist) {
      return DownloadContent();
    } else if (playList is HlsMasterPlaylist) {
      List<Qualities> qualities = [];
      log(playList.variants.first.url.toString());
      final lang = playList.audios.first.format.language;
      final langName = playList.audios.first.name;
      final audioHls = playList.audios.first.url.toString();
      final audioCodec = playList.audios.first.format.codecs;

      for (final variant in playList.variants) {
        qualities.add(
          Qualities(
            height: variant.format.height,
            width: variant.format.width,
            url: variant.url.toString(),
            bandWidth: variant.format.bitrate,
            codec: variant.format.codecs,
          ),
        );
      }

      final result = DownloadContent(
        codecAudio: audioCodec,
        qualities: qualities,
        url: url,
        audio: audioHls,
        lang: lang,
        langName: langName,
      );
      return result;
    } else {
      throw 'Unable to recognize HLS playlist type';
    }
  }

  @override
  List<String> pathSegments(String url) {
    final segments = url.split('/');
    return segments.sublist(0, segments.length - 1);
  }

  Future<List<String>> dLoad(List<String> urls, Map<String, String> headers,
      Function(StreamController<double> stream) streamer) async {
    final downloadDirs = <Directory>[];
    final files = <File>[];
    final mediaSegments = [];
    final totalSegments = <int>[];
    final filenames = urls.map(getFilePath).toList();
    final appDocDir = await getApplicationDocumentsDirectory();

    // Create download directories for each file
    for (final url in urls) {
      final downloadDir =
          Directory(p.join(appDocDir.path, url.hashCode.toString()));
      if (!await downloadDir.exists()) {
        await downloadDir.create();
      }
      downloadDirs.add(downloadDir);
    }

    // Check if files exist, otherwise download them
    for (int i = 0; i < urls.length; i++) {
      final filepath = p.join(downloadDirs[i].path, filenames[i]);
      var file = File(filepath);
      if (!await file.exists()) {
        file = await downloadFile(
            urls[i], downloadDirs[i].path, filenames[i], headers);
      }
      files.add(file);
      final lines = await file.readAsLines();
      final segments = await getHlsMediaFiles(Uri.parse(file.path), lines);
      mediaSegments.add(segments);
      totalSegments.add(segments.length);
    }

    // Download segments for each file, and report progress
    final total = totalSegments.reduce((value, element) => value + element);
    var currentProgress = 0.0;
    var finishedCount = 0;
    final controller = StreamController<double>();
    while (finishedCount < urls.length) {
      var progressSum = 0.0;
      for (int i = 0; i < urls.length; i++) {
        final segments = mediaSegments[i];
        if (segments.isNotEmpty) {
          final seg = segments.first;
          final urlToDownload =
              p.join(pathSegments(urls[i]).join('/'), seg.url);
          var ff = File(p.join(downloadDirs[i].path, seg.url));
          if (!await ff.exists()) {
            await downloadFile(
                urlToDownload, downloadDirs[i].path, seg.url!, headers);
          }
          segments.removeAt(0);
          if (segments.isEmpty) {
            finishedCount++;
          }
          progressSum += (1 / total) * 100 / urls.length;
        }
      }
      currentProgress += progressSum;
      controller.add(currentProgress);
      log("\n===== Download Progress: $currentProgress % =====");
      await streamer(controller);
    }

    return files.map((file) => file.absolute.path).toList();
  }
}

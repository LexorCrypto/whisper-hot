# Custom Sounds

Place CC0-licensed AIFF sound files here:
- start.aiff  (recording started, soft pop)
- stop.aiff   (recording stopped, quiet click)
- done.aiff   (transcription complete, pleasant chime)

Download from freesound.org (CC0 license) and convert to AIFF:
  ffmpeg -i downloaded.wav -f aiff start.aiff

Until custom sounds are added, SoundPlayer falls back to
macOS system sounds (Morse, Tink, Glass).

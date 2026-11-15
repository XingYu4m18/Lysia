# Third-party components

Flutter and Dart dependencies are pinned by pubspec.lock. Their notices are included in the Flutter build's NOTICES.Z file. Windows uses the Microsoft WebView2 Runtime installed on the machine.

The Windows runner scaffolding and other Flutter-generated template code retain Flutter's BSD 3-Clause terms; see licenses/Flutter-LICENSE. The project's PolyForm license applies to original project code and does not replace these third-party terms.

## NetEase AFP runtime

The locally tested assets/afp/afp.js and assets/afp/afp.wasm.js were copied, without algorithm changes, from:
https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/tree/main/public/audio_match_demo

That example credits https://github.com/mos9527/ncm-afp and the NetEase browser extension implementation. The credited upstream repository was unavailable at the time of this prototype. The actual redistribution rights of these algorithm assets have not been independently established; verify permission before public distribution. This notice does not assert a license grant.

These two runtime files are excluded from this public source repository. The enclosing API project's root MIT license alone is not treated here as proof of the original algorithm assets' redistribution rights. See assets/afp/README.md for provenance and checksums. Existing local builds are not public releases.

## Recognition protocol references

NetEase request structure:
https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/blob/main/module/audio_match.js

KuGou request protocol and signing reference:
https://github.com/zhzipu/LX-N-X-Music/blob/main/src/core/musicRecognition/engines/kugou.ts

The Dart adapters implement these request formats. Availability of a client-facing endpoint is not a guarantee of service or a grant of platform authorization.

## Test fixtures

Verification uses a separately downloaded public test fixture from ShazamIO:
https://github.com/shazamio/ShazamIO/blob/master/examples/data/Gloria.ogg

The music test fixture is not included in the application bundle.

## OGG Vorbis decoding

windows/runner/vendor/stb_vorbis.c comes from https://github.com/nothings/stb/blob/master/stb_vorbis.c . The upstream file includes its public-domain/MIT alternative licensing text. It is compiled into the app for OGG Vorbis decoding; the complete bundled source retains that notice. Windows Media Foundation handles the other supported audio formats using installed system codecs.

FFmpeg was used solely outside the application to prepare test files. No FFmpeg executable or libraries are included in the distributed application.

### stb_vorbis MIT notice

ALTERNATIVE A - MIT License
Copyright (c) 2017 Sean Barrett
Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


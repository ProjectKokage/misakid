# Third-party notices

This package is Apache-2.0. It contains a behavior-preserving Dart adaptation
of the byte-BPE stage used by pinned Misaki's English transformer mode, exact
generated Unicode-property tables, and strict readers for selected external
spaCy/Thinc model resources. The external model is supplied by the caller and
is never bundled, downloaded, or relicensed by this package.

## Misaki reference implementation

- Project: Misaki
- Source: https://github.com/hexgrad/misaki
- Pinned commit: `fba1236595f2d2bf21d414ba6e57d25256afada3`
- Version: 0.9.4
- License: Apache-2.0

The package's [LICENSE](LICENSE) contains the complete Apache License 2.0.

## External `en_core_web_trf==3.8.0` model

The reviewed caller-supplied wheel is:

```text
https://github.com/explosion/spacy-models/releases/download/en_core_web_trf-3.8.0/en_core_web_trf-3.8.0-py3-none-any.whl
Bytes: 457421864
SHA-256: 272a31e9d8530d1e075351d30a462d7e80e31da23574f1b274e200f3fff35bf5
```

Its metadata names Explosion as author and declares MIT. Its packaged
`LICENSE` is 1,056 bytes with SHA-256
`3933c176979b68bc6d0bcc902c7d6c130f1d127f476f17ba5cdba8d99cfd0012`:

```text
Copyright 2021 ExplosionAI GmbH

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
```

The wheel's `LICENSES_SOURCES` is 2,627 bytes with SHA-256
`e94b3033acaecc8b3515a9b8d59917ef0d0ded835a281dbe7185afaf2953122a`.
It records:

- OntoNotes 5, commercial data licensed by Explosion;
- ClearNLP Constituent-to-Dependency Conversion, with a citation provided for
  reference and no code packaged with the model;
- WordNet 3.0 under the WordNet 3.0 License; and
- `roberta-base`, attributed to Yinhan Liu, Myle Ott, Naman Goyal, Jingfei Du,
  Mandar Joshi, Danqi Chen, Omer Levy, Mike Lewis, Luke Zettlemoyer, and
  Veselin Stoyanov, linking to
  https://github.com/pytorch/fairseq/tree/master/examples/roberta.

The packaged source ledger leaves the `roberta-base` license field empty.
Misakid does not infer a missing license, grant rights to the external weights,
or replace the wheel's notices. Callers acquiring or redistributing the model
must review and retain its complete `LICENSE` and `LICENSES_SOURCES` files.

The WordNet notice embedded in the wheel is:

```text
WordNet Release 3.0

This software and database is being provided to you, the LICENSEE, by
Princeton University under the following license. By obtaining, using and/or
copying this software and database, you agree that you have read, understood,
and will comply with these terms and conditions.:

Permission to use, copy, modify and distribute this software and database and
its documentation for any purpose and without fee or royalty is hereby
granted, provided that you agree to comply with the following copyright notice
and statements, including the disclaimer, and that the same appear on ALL
copies of the software, database and documentation, including modifications
that you make for internal use or for distribution.

WordNet 3.0 Copyright 2006 by Princeton University. All rights reserved.

THIS SOFTWARE AND DATABASE IS PROVIDED "AS IS" AND PRINCETON UNIVERSITY MAKES
NO REPRESENTATIONS OR WARRANTIES, EXPRESS OR IMPLIED. BY WAY OF EXAMPLE, BUT
NOT LIMITATION, PRINCETON UNIVERSITY MAKES NO REPRESENTATIONS OR WARRANTIES OF
MERCHANT-ABILITY OR FITNESS FOR ANY PARTICULAR PURPOSE OR THAT THE USE OF THE
LICENSED SOFTWARE, DATABASE OR DOCUMENTATION WILL NOT INFRINGE ANY THIRD PARTY
PATENTS, COPYRIGHTS, TRADEMARKS OR OTHER RIGHTS.

The name of Princeton University or Princeton may not be used in advertising
or publicity pertaining to distribution of the software and/or database.
Title to copyright in this software, database and any associated documentation
shall at all times remain with Princeton University and LICENSEE agrees to
preserve same.
```

## spaCy 3.8.4 and Thinc 8.3.4

The shared tokenizer boundary and serialized tagger-graph contract preserve
behavior from spaCy 3.8.4 and Thinc 8.3.4. No Python package or native spaCy or
Thinc binary is distributed or invoked at runtime.

spaCy 3.8.4 is MIT, with license-file SHA-256
`3f4378e67708fecacd3e27651c8bc0f977cf20789e19da0d81a2840e7cf573a2`:

```text
The MIT License (MIT)

Copyright (C) 2016-2024 ExplosionAI GmbH, 2016 spaCy GmbH, 2015 Matthew Honnibal

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Thinc 8.3.4 is MIT, with license-file SHA-256
`d7192459f33a5d8c66358e2115ccbd3265478750f0b9d15f0c22e68e3ce6cc1e`.
Its notice is the same MIT text above with:

```text
Copyright (C) 2016 ExplosionAI GmbH, 2016 spaCy GmbH, 2015 Matthew Honnibal
```

## Curated tokenizer and transformer behavior

The byte mapping, split contract, and ranked-merge behavior are adapted from
`curated-tokenizers==0.0.9`, specifically its reviewed `_bbpe.pyx` and
`merges.cc` behavior. The exact upstream license file has SHA-256
`49d8fef96cd92719cb5242ef4c4f954edc008a46fcf7caabecae14dbcc444b50`.

```text
The MIT License (MIT)

Copyright (C) 2022 ExplosionAI GmbH

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

That license records that the BPE byte mapping and split pattern came directly
from GPT-2 and includes this notice:

```text
Software Copyright (c) 2019 OpenAI

We don't claim ownership of the content you create with GPT-2, so it is yours
to do with as you please. We only ask that you use GPT-2 responsibly and
clearly indicate your content was created using GPT-2.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software. The above copyright notice and
this permission notice need not be included with content created by the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The exact reference environment also uses `curated-transformers==0.1.1` and
`spacy-curated-transformers==0.3.0`. Both declare MIT and carry the same
license-file SHA-256
`e4f2431f403ea0d20d108bbe1f0615a4ca3b6b765e2dbafae93908d3986d153a`:

```text
The MIT License (MIT)

Copyright (C) 2021-2023 ExplosionAI GmbH

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## `regex==2024.11.6` and Unicode 16.0.0 data

The generated Letter, Number, and White_Space ranges reproduce the exact
Unicode-property answers returned by `regex==2024.11.6`. The `regex` metadata
reports Unicode 16.0.0. Neither the Python module nor its binary is bundled or
used at runtime.

Its exact `LICENSE.txt` has SHA-256
`bff55ef4cdcc8c14ce259f8e8ab60e264418440d6335f4dc138273fbd506144d`
and states:

```text
This work was derived from the 're' module of CPython 2.6 and CPython 3.1,
copyright (c) 1998-2001 by Secret Labs AB and licensed under CNRI's Python 1.6
license.

All additions and alterations are licensed under the Apache 2.0 License.
```

The package's Apache-2.0 [LICENSE](LICENSE) accompanies the generated
adaptation. Unicode data is additionally covered by Unicode License v3:

```text
UNICODE LICENSE V3 COPYRIGHT AND PERMISSION NOTICE

Copyright © 1991-2026 Unicode, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of data files and any associated documentation (the "Data Files") or software
and any associated documentation (the "Software") to deal in the Data Files
or Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, and/or sell copies of the Data
Files or Software, and to permit persons to whom the Data Files or Software
are furnished to do so, provided that either (a) this copyright and permission
notice appear with all copies of the Data Files or Software, or (b) this
copyright and permission notice appear in associated Documentation.

THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF THIRD
PARTY RIGHTS.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE BE
LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES, OR
ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA FILES OR SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall not
be used in advertising or otherwise to promote the sale, use or other dealings
in these Data Files or Software without prior written authorization of the
copyright holder.
```

## Dart `crypto` 3.0.7

Runtime SHA-256 validation uses `crypto` 3.0.7 under BSD-3-Clause:

```text
Copyright 2015, the Dart project authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Google LLC nor the names of its contributors may be
      used to endorse or promote products derived from this software without
      specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
```

## Native execution

The supported macOS-arm64 Apple Accelerate path is package-owned Apache-2.0
source with reproducible build tooling. No compiled native artifact is
distributed and no Apple framework code is copied by this package. The shim
links to the system Accelerate framework and consumes only the explicit,
caller-supplied model described above.

## Python reference tooling

Python 3.12, spaCy, Thinc, Torch, curated packages, and `regex` are used only
in explicitly provisioned repository oracle and inspection tooling. They are
not production dependencies, are excluded from the published package, and are
never invoked or downloaded during conversion.

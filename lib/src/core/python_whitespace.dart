/// Whether [scalar] is whitespace to CPython 3.12's `str.isspace`,
/// `str.split` and `str.strip`.
///
/// CPython uses the bidirectional WS, B and S characters, Unicode Zs, and the
/// four historic ASCII information separators U+001C..U+001F.
bool isPythonWhitespace(int scalar) =>
    (scalar >= 0x09 && scalar <= 0x0d) ||
    (scalar >= 0x1c && scalar <= 0x20) ||
    scalar == 0x85 ||
    scalar == 0xa0 ||
    scalar == 0x1680 ||
    (scalar >= 0x2000 && scalar <= 0x200a) ||
    scalar == 0x2028 ||
    scalar == 0x2029 ||
    scalar == 0x202f ||
    scalar == 0x205f ||
    scalar == 0x3000;

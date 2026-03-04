# Ben Eater tutorial: Binary to decimal can’t be that hard, right?

Tutorial : https://www.youtube.com/watch?v=v3-a-zqKfgA&t=2497 \
Result   : https://www.youtube.com/watch?v=v3-a-zqKfgA&t=2497

This implementation does not contain the full binary to decimal conversion
code from the tutorial video. The stdlib (standaard BREADBOX subroutines that
can be included in projects) provides the subroutine `fmtdec16` for exactly
this purpose.

The code for the stdlib implementation of "binary to decimal" can be found in
the repository at `breadbox/stdlib/math/`. One difference with Ben's code, is
that I split off the division code into a general purpose `divmod16` subroutine,
which is called with a divisor of 10 from the `fmtdec16` subroutine repeatedly,
to strip off the decimal "ones" from the binary number.

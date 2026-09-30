#!/usr/bin/env bash
# Open the OSC 8 hyperlink or plaintext URL under a tmux copy-mode cursor.
set -euo pipefail

if [[ ${1:-} == --selection ]]; then
    selection=$(cat)
    [[ -n $selection ]] && open "$selection"
    exit 0
fi

pane_id=${1:?usage: tmux-open-url-at-cursor.sh PANE_ID}
hyperlink=$(tmux display-message -p -t "$pane_id" -F '#{copy_cursor_hyperlink}')
if [[ -n $hyperlink ]]; then
    open "$hyperlink"
    exit 0
fi

cursor_x=$(tmux display-message -p -t "$pane_id" -F '#{copy_cursor_x}')
cursor_y=$(tmux display-message -p -t "$pane_id" -F '#{copy_cursor_y}')

url=$(
    tmux capture-pane -p -M -N -F -t "$pane_id" |
        CURSOR_X="$cursor_x" CURSOR_Y="$cursor_y" /usr/bin/perl -MEncode=decode -MUnicode::UCD=charinfo -0e '
            use strict;
            use utf8;
            use warnings;

            my $cursor_x = $ENV{CURSOR_X};
            my $cursor_y = $ENV{CURSOR_Y};
            exit if !defined($cursor_x) || !defined($cursor_y);

            my $capture = decode("UTF-8", do { local $/; <STDIN> });
            my @rows = split(/\n/, $capture, -1);
            pop @rows if @rows && $rows[-1] eq q{};
            exit if $cursor_y > $#rows;

            my (@flags, @text);
            for my $row (@rows) {
                $row =~ s/^(\S*) // or exit;
                push @flags, $1;
                push @text, $row;
            }

            # A W flag means that this physical row wraps into the next one.
            # Reconstruct just the logical line containing the cursor.
            my $start = $cursor_y;
            $start-- while $start > 0 && $flags[$start - 1] =~ /W/;
            my $end = $cursor_y;
            $end++ while $end < $#text && $flags[$end] =~ /W/;

            my $prefix = join(q{}, @text[$start .. $cursor_y - 1]);
            my $line = join(q{}, @text[$start .. $end]);

            sub cell_width {
                my ($character) = @_;
                my $info = charinfo(ord($character));
                return 0 if $info->{category} =~ /^(?:Mn|Me|Cf)$/;

                my $codepoint = ord($character);
                return 2 if
                    ($codepoint >= 0x1100 && $codepoint <= 0x115F) ||
                    ($codepoint >= 0x2329 && $codepoint <= 0x232A) ||
                    ($codepoint >= 0x2E80 && $codepoint <= 0xA4CF) ||
                    ($codepoint >= 0xAC00 && $codepoint <= 0xD7A3) ||
                    ($codepoint >= 0xF900 && $codepoint <= 0xFAFF) ||
                    ($codepoint >= 0xFE10 && $codepoint <= 0xFE19) ||
                    ($codepoint >= 0xFE30 && $codepoint <= 0xFE6F) ||
                    ($codepoint >= 0xFF00 && $codepoint <= 0xFF60) ||
                    ($codepoint >= 0xFFE0 && $codepoint <= 0xFFE6) ||
                    ($codepoint >= 0x1F000 && $codepoint <= 0x1FAFF) ||
                    ($codepoint >= 0x20000 && $codepoint <= 0x3FFFD);
                return 1;
            }

            # tmux reports cursor_x in terminal cells; Perl string offsets are
            # Unicode characters. Translate it so a preceding wide character
            # does not shift URL detection.
            sub character_offset_at_cell {
                my ($text, $cell) = @_;
                my $width = 0;
                my $offset = 0;
                for my $character (split(//, $text)) {
                    last if $width >= $cell;
                    $width += cell_width($character);
                    $offset++;
                }
                return $offset;
            }

            sub clean_url {
                my ($url) = @_;

                # Sentence punctuation and unmatched closing delimiters are not
                # part of a URL, but can immediately follow one in prose.
                $url =~ s/[.,;:!?]+$//;
                for my $delimiter (["(", ")"], ["[", "]"], ["{", "}"]) {
                    while ($url =~ /\Q$delimiter->[1]\E$/) {
                        my $opens = () = $url =~ /\Q$delimiter->[0]\E/g;
                        my $closes = () = $url =~ /\Q$delimiter->[1]\E/g;
                        last if $opens >= $closes;
                        chop $url;
                    }
                }
                return $url;
            }

            my $url_pattern = qr{(?<![[:alnum:]_])((?:(?:https?|ftp)://|www\.)[^\s<>"\x27]+)};

            sub table_url_at_cursor {
                my ($text, $cursor_y, $cursor_x, $pattern) = @_;
                my $current = $text->[$cursor_y];
                my $cursor_character = character_offset_at_cell($current, $cursor_x);
                my @current_characters = split(//, $current);
                my ($left, $right);

                for (my $index = $cursor_character - 1; $index >= 0; $index--) {
                    if ($current_characters[$index] =~ /[│┃║]/) {
                        $left = $index;
                        last;
                    }
                }
                for (my $index = $cursor_character; $index < @current_characters; $index++) {
                    if ($current_characters[$index] =~ /[│┃║]/) {
                        $right = $index;
                        last;
                    }
                }
                return if !defined($left) || !defined($right);

                my $cursor_in_cell = $cursor_character - $left - 1;
                my @cells;
                for my $row (0 .. $#$text) {
                    my $line = $text->[$row];
                    next if length($line) <= $right;
                    next if substr($line, $left, 1) !~ /[│┃║]/;
                    next if substr($line, $right, 1) !~ /[│┃║]/;
                    $cells[$row] = substr($line, $left + 1, $right - $left - 1);
                }

                for my $row (0 .. $#cells) {
                    next if !defined($cells[$row]);
                    while ($cells[$row] =~ /$pattern/g) {
                        my ($url_start, $url_end) = ($-[1], $+[1]);
                        my $first_piece = $1;
                        my $first_clean = clean_url($first_piece);
                        next if $first_clean eq q{};

                        my $at_cell_end = substr($cells[$row], $url_end) =~ /^\s*$/;
                        my $first_start = $url_start;
                        $first_start-- if $first_start > 0 &&
                            substr($cells[$row], $first_start - 1, 1) =~ /[\(\[]/;
                        my @segments = ({
                            row => $row,
                            start => $first_start,
                            # Include an enclosing closing delimiter as a hit
                            # target, while leaving it out of the opened URL.
                            end => $url_end,
                        });
                        my $assembled = $first_clean;
                        my $complete = length($first_clean) < length($first_piece) || !$at_cell_end;

                        # Pi tables hard-wrap a long cell as separate output
                        # rows, not tmux W-flag soft wraps. If this URL reaches
                        # a cell edge, join following fragments only when one
                        # ends in punctuation that conclusively closes the URL.
                        if (!$complete && $at_cell_end) {
                            for my $next_row ($row + 1 .. $#cells) {
                                next if !defined($cells[$next_row]);
                                my $next_cell = $cells[$next_row];
                                last if $next_cell =~ /[─━┄┅┈┉]/;
                                next if $next_cell =~ /^\s*$/;
                                last if $next_cell !~ /^(\s*)([^\s<>"\x27]+)/;

                                my ($leading, $piece) = ($1, $2);
                                my $piece_start = length($leading);
                                my $piece_clean = clean_url($piece);
                                $assembled .= $piece_clean;
                                push @segments, {
                                    row => $next_row,
                                    start => $piece_start,
                                    end => $piece_start + length($piece),
                                };

                                if (length($piece_clean) < length($piece)) {
                                    $complete = 1;
                                    last;
                                }
                            }
                        }

                        # Do not turn an adjacent table row into a URL merely
                        # because an unparenthesized URL happened to end at a
                        # cell edge. Keep its first, already-valid segment.
                        if (!$complete) {
                            $assembled = $first_clean;
                            @segments = ($segments[0]);
                        }

                        for my $segment (@segments) {
                            next if $cursor_y != $segment->{row};
                            if ($cursor_in_cell >= $segment->{start} &&
                                $cursor_in_cell < $segment->{end}) {
                                return $assembled;
                            }
                        }
                    }
                }
                return;
            }

            my $table_url = table_url_at_cursor(\@text, $cursor_y, $cursor_x, $url_pattern);
            if (defined($table_url)) {
                $table_url = "https://$table_url" if $table_url =~ /^www\./;
                print $table_url;
                exit;
            }

            my $cursor = length($prefix) +
                character_offset_at_cell($text[$cursor_y], $cursor_x);

            while ($line =~ /$url_pattern/g) {
                my ($start_offset, $end_offset) = ($-[1], $+[1]);
                my $url = clean_url($1);
                $start_offset-- if $start_offset > 0 &&
                    substr($line, $start_offset - 1, 1) =~ /[\(\[]/;

                if ($cursor >= $start_offset && $cursor < $end_offset) {
                    $url = "https://$url" if $url =~ /^www\./;
                    print $url;
                    exit;
                }
            }
        '
)

if [[ -z $url ]]; then
    tmux display-message -d 2000 -t "$pane_id" 'No URL under copy-mode cursor'
    exit 0
fi

open "$url"

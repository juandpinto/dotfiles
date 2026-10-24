# Generated colors only; never rebind keys during a theme switch.
set -g status-style 'fg={{ foreground }},bg=default'
set -g message-style 'fg={{ foreground }},bg={{ selection }}'
set -g pane-border-style 'fg={{ muted }}'
set -g pane-active-border-style 'fg={{ accent }}'
set -g window-status-style 'fg={{ muted }},bg=default'
set -g window-status-current-style 'fg={{ green }},bg=default,bold'
set -g status-left-style 'fg={{ blue }},bg=default'
set -g status-right-style 'fg={{ blue }},bg=default'
# Restore default backgrounds after Omarchy's stock retint, preserving opacity.
set -g window-style 'fg=default,bg=default'
set -g window-active-style 'fg=default,bg=default'

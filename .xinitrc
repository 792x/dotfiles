nvidia-settings --load-config-only &
xrandr --output DP-0 --primary &
[[ -f ~/.Xresources ]] && xrdb -merge ~/.Xresources &
~/.fehbg &
discord &
pidgin &
exec i3

nvidia-settings --load-config-only &
[[ -f ~/.Xresources ]] && xrdb -merge ~/.Xresources &
~/.fehbg &
exec i3

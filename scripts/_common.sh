#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

_git_clone_or_pull() {
    repo_dir="$1"
    repo_url="${2:-}"

    if [[ -z "$repo_url" ]]; then
        repo_url=$(ynh_read_manifest --manifest_key="upstream.code")
    fi

    if [ -d "$repo_dir" ]; then
        ynh_exec_as "$app" git -C "$repo_dir" fetch --quiet
    else
        ynh_exec_as "$app" git clone "$repo_url" "$repo_dir" --quiet
    fi
    ynh_exec_as "$app" git -C "$repo_dir" pull --quiet
}

#=================================================
# FUTURE OFFICIAL HELPERS
#=================================================

ynh_maintenance_mode_ON () {
    # Create an html to serve as maintenance notice
    cat > "/var/www/html/maintenance.$app.html" <<EOF
<!DOCTYPE html>
<html>
    <head>
        <meta http-equiv="refresh" content="3">
        <title>Your app $app is currently under maintenance!</title>
        <style>
            body {
                width: 70em;
                margin: 0 auto;
            }
        </style>
    </head>
    <body>
        <h1>Your app $app is currently under maintenance!</h1>
        <p>This app has been put under maintenance by your administrator at $(date)</p>
        <p>Please wait until the maintenance operation is done. This page will be reloaded as soon as your app will be back.</p>
    </body>
</html>
EOF

    # Create a new nginx config file to redirect all access to the app to the maintenance notice instead.
    cat > "/etc/nginx/conf.d/$domain.d/maintenance.$app.conf" <<EOF
# All request to the app will be redirected to ${path}_maintenance and fall on the maintenance notice
rewrite ^${path}/(.*)$ ${path}_maintenance/? redirect;
# Use another location, to not be in conflict with the original config file
location ${path}_maintenance/ {
    alias /var/www/html/ ;
    try_files maintenance.$app.html =503;

    # Include SSOWAT user panel.
    include conf.d/yunohost_panel.conf.inc;
}
EOF

    # The current config file will redirect all requests to the root of the app.
    # To keep the full path, we can use the following rewrite rule:
    # rewrite ^${path}/(.*)$ ${path}_maintenance/\$1? redirect;
    # The difference will be in the $1 at the end, which keep the following queries.
    # But, if it works perfectly for a html request, there's an issue with any php files.
    # This files are treated as simple files, and will be downloaded by the browser.
    # Would be really be nice to be able to fix that issue. So that, when the page is reloaded after the maintenance, the user will be redirected to the real page he was.
    systemctl reload nginx
}

ynh_maintenance_mode_OFF () {
    # Rewrite the nginx config file to redirect from ${path}_maintenance to the real url of the app.
    echo "rewrite ^${path}_maintenance/(.*)$ ${path}/\$1 redirect;" > "/etc/nginx/conf.d/$domain.d/maintenance.$app.conf"
    systemctl reload nginx

    # Sleep 4 seconds to let the browser reload the pages and redirect the user to the app.
    sleep 4

    # Then remove the temporary files used for the maintenance.
    rm "/var/www/html/maintenance.$app.html"
    rm "/etc/nginx/conf.d/$domain.d/maintenance.$app.conf"

    systemctl reload nginx
}
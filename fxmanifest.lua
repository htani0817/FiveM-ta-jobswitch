fx_version 'cerulean'
game 'gta5'

name 'ta-jobswitch'
description 'Switch between held jobs with the J key, toggle duty, and let admins take any job'
author 'Tani'
version '2.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_script 'client.lua'

server_script 'server.lua'

dependencies {
    'ox_lib',
    'qbx_core'
}

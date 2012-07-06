express = require 'express'

Server = require('./socket').Server

server = new Server process.env.PORT || 8081

if not module.parent
  server.start (done) ->
    console.log "Server successfull started"

module.exports.start = (done)->
  server.start () ->
    console.log "Server successfull started"
    done()
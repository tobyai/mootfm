async = require "async"

class exports.Server

  constructor: (@port) ->

    User = require './models/user'
    flash = require 'connect-flash'

    @connect = require 'connect'
    @cookie = require 'cookie'


    express = require 'express'
    path = require 'path'
    
    MemoryStore = express.session.MemoryStore
    @sessionStore = new MemoryStore()

    @conf = require './lib/conf'
    Security = require('./lib/security').Security
    @app = express()

    Dispatcher = require('./lib/dispatcher')
    @dispatcher = new Dispatcher()

    # convert existing coffeescript, styl, and less resources to js and css for the browser
    @app.use require('connect-assets')()

    # browserify for concatenation of the client js
    bundle = require('browserify')
      entry: path.resolve(__dirname,'./assets/js/controler.coffee')
      watch: true
      debug: true

    bundle.on 'syntaxError', (err) ->
      console.error err
      process.exit 1

    @app.use bundle

    @app.set('views', __dirname + '/views')
    @app.set('view engine', 'jade')
    @app.use(express.bodyParser())
    @app.use(express.methodOverride())
    @app.use(require('stylus').middleware({ src: __dirname + '/public' }))
    @app.use(express.static(__dirname + '/public'))
    @app.use(express.cookieParser('test'))
    @app.use(express.session { secret :'test', store: @sessionStore, key: 'sessionID'})
    @app.use(flash())

    #development
    @app.use(express.errorHandler({
      dumpExceptions: true, showStack: true
    }))

    #production
    security = new Security
    security.init @app, (error, passport) =>
      @app.use(@app.router)

  start: (callback) ->
    User = require './models/user'
    Statement = require './models/statement'

    console.log 'Server starting'
    @http_server=@app.listen @port
    console.log 'Server listening on port ' + @port

    @app.get '/', (req, res) ->
      console.log "redirect called "
      res.render('home', {user: req.user, message: req.flash('error')})

    @app.get '/success', (req, res) ->
      res.render('home', {user: req.user, message: req.flash('error')})

    @app.get '/login', (req, res) ->
      res.render('login', {user: req.user, message: req.flash('error')})

    @app.get '/register', (req, res) ->
      res.render('register', {userData: {}, message: req.flash('error')})

    @app.get '/loggedin', (req, res) ->
      res.render('loggedin', {user: req.user, message: req.flash('error')})

    @app.get '/logout', (req, res) ->
      #TODO: rethink if it is possible over socketID -> without
      req.logOut()
      backURL=req.header('Referer') || '/'
      res.redirect(backURL);

    @app.post '/register', (req, res) ->
      newUserAttributes =
        username : req.body.username
        password : req.body.password
        email : req.body.email
        name : req.body.name
      User.validateUser newUserAttributes, (errors) ->
        if (errors.length)
          res.render('register', {errors: errors, userData: newUserAttributes})
        else
          User.create newUserAttributes, (err, user) ->
            if (err)
              res.render('register', {errors: errors, userData: newUserAttributes})
            else
              res.redirect('/login')

    @app.get '/statement', (req, res) ->
      res.render('statement', {user: req.user, message: req.flash('error')})

# Socket IO
    @io = require('socket.io').listen @http_server

    @io.set "authorization", (data, accept) =>
      console.log "authorization called"
      if data.headers.cookie
        cookie = @cookie.parse(data.headers.cookie)
      else
        cookie = data.query
      # NOTE: To detect which session this socket is associated with,
      #   *       we need to parse the cookies.

      return accept("Session cookie required.", false)  unless cookie

      # NOTE: Next, verify the signature of the session cookie.
      data.cookie = @connect.utils.parseSignedCookies(cookie, 'test')

      # NOTE: save ourselves a copy of the sessionID.
      data.sessionID = data.cookie["sessionID"]
      @sessionStore.get data.sessionID, (err, session) ->
        if err
          return accept("Error in session store.", false)
        else return accept("Session not found.", false)  unless session
        if (!session.passport.user)
          return accept("User in session not found.", false)
        # success! we're authenticated with a known session.
        data.session = session
        data.user = session.passport.user
        accept null, true


    @io.sockets.on "connection", (socket) =>
      hs = socket.handshake
      console.log "establishing connection"
      User.get_by_username hs.user, (err, user) =>
        if err
          console.log "Couldnt find user:", user 
          return
        else
          socket.user= user
          user.socket= socket
          console.log "A socket with sessionID " + hs.sessionID + " and username: " + user.username + " connected."
          socket.emit "loggedin", user.username

      socket.on "register", (id)=>
        if socket.user.page_id
          @dispatcher.unregister socket.user, socket.user.page_id, (err)->
            console.log "ERROR while unregistering page:", err if err

        socket.user.page_id=id
        @dispatcher.register socket.user, id, (err)->
          console.log "ERROR while registering page:", err if err

      socket.on 'post', (statement_json) =>
        console.log "Socket IO: new statement", statement_json
        async.waterfall [
          (callback)=>
            Statement.create statement_json, callback

          (stmt, callback) =>
            if statement_json.parent && statement_json.side
              Statement.get statement_json.parent, (err,parent) ->
                return callback err if err
                stmt.argue parent, statement_json.side, (err)->
                  callback err, stmt, parent
            else
              callback null, stmt, null

          (stmt, parent, callback) =>
            stmt.get_all_points 0, (err, points) =>
              callback null, parent, points

          (parent, points, callback) =>
            point=points[0]
            if parent
              point.parent=parent.id
              point.vote=0
              point.side=statement_json.side
            @dispatcher.dispatch [point], (err)->
              callback err, point
          (point, callback)->
            point.cid=statement_json.cid if statement_json.cid
            socket.emit "statement", [point]
            callback null
            
        ], (err) ->
          return console.log "Error occured", err if err

      socket.on 'get', (id) =>
        async.waterfall [
          (callback)->
            if id
              callback()  
            else 
              callback "No id specified for GET on Socket IO!" 
          (callback) ->
            Statement.get id, callback
          (stmt, callback) ->
            stmt.get_all_points 1, callback
          (points, callback) ->
            socket.emit "statement", points
            callback()
        ], (err) ->
          return console.log "Error occured", err if err

      socket.on 'vote', (stmt_json, amount) =>
        async.waterfall [
          (callback)->
            if stmt_json and amount
              callback()  
            else 
              callback "Wrong parameters for vote!" 
            console.log "post vote"
          (callback) ->
            if amount!=-1 and amount!=1
              callback "Wrong vote amount for vote!" 
            else
              callback()
          (callback) ->
            async.map [stmt_json.parent, stmt_json.id], (item,callback)->
              Statement.get item, callback
            , (err, [stmt, point]) ->
              callback null, stmt, point
          (stmt, point, callback) ->
            socket.user.vote stmt, point, stmt_json.side, amount, (err, total_votes)->
              callback null, stmt, point, total_votes
          (stmt, point, total_votes, callback) ->
            point.get_all_points 0, (err, points)->
              points[0].vote= total_votes
              points[0].parent= stmt.id
              callback null, points
          (points, callback) => 
            socket.emit "statement", points
            @dispatcher.dispatch points, callback
        ], (err) ->
          return console.log "Error occured", err if err

      socket.on "disconnect", ->
        console.log "A socket with sessionID " + hs.sessionID + " disconnected."
    callback()

  stop: (callback) ->
    @io.server.close()
    callback()

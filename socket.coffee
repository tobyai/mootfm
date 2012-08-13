async = require "async"

class exports.Server

  constructor: (@port) ->

    User = require './models/user'

    express = require 'express'

    @user = new User 'test@gmail.com', 'test@gmail.com', 'test'
    @userTmpList = [ @user ]

    @conf = require './lib/conf'
    Security = require('./lib/security').Security
    @app = express.createServer()

    # convert existing coffeescript, styl, and less resources to js and css for the browser
    @app.use require('connect-assets')()

    @app.use express.bodyParser()


    @app.set('views', __dirname + '/views')
    @app.set('view engine', 'jade')
    @app.use(express.bodyParser())
    @app.use(express.methodOverride())
    @app.use(require('stylus').middleware({ src: __dirname + '/public' }))
    @app.use(express.static(__dirname + '/public'))
    @app.use(express.cookieParser())
    @app.use(express.session { secret :'test'})

    #development
    @app.use(express.errorHandler({
      dumpExceptions: true, showStack: true
    }))

    #production
    #@app.use(express.errorHandler())
    security = new Security
    security.init @app, (error, passport) =>
      @app.use(@app.router)

  start: (callback) ->
    User = require './models/user'
    Statement = require './models/statement'

    console.log 'Server starting'
    @app.listen @port
    console.log 'Server listening on port ' + @port

    @app.get '/', (req, res) ->
      res.render('home', {user: req.user, message: req.flash('error')})

    @app.get '/login', (req, res) ->
      res.render('login', {user: req.user, message: req.flash('error')})

    @app.get '/register', (req, res) ->
      res.render('register', {userData: {}, message: req.flash('error')})

    @app.get '/logout', (req, res) ->
      req.logOut()
      res.redirect('/')

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
      res.render 'statement', {}

# REST API
    version = "v0"
    url_prefix='/' + version
    @app.get url_prefix + "/statement/:id", (req, res) ->
      console.log "get statement"
      Statement.get req.params.id, (err,stmt) ->
        console.log "Error occured while loading statement:", err if err
        return res.status(404).send {error:err} if err
        stmt.get_representation 1, (err, representation) ->
          console.log "Error occured while converting statement:", err if err
          return res.status(500).send {error:err} if err
          if not representation["sides"]["pro"]
            representation["sides"]["pro"]=[]
          if not representation["sides"]["contra"]
            representation["sides"]["contra"]=[]
          console.log "Delivering Statement:\n", JSON.stringify(representation, null, 2)
          return res.send representation

    @app.post url_prefix + '/statement', (req, res) ->
      console.log "post statement"
      Statement.create {title: req.body.title}, (err,stmt) ->
        return res.status(500).send {error:err} if err
        return res.status(201).send {id:stmt.id}

    #make a new argument
    @app.post url_prefix+'/statement/:id/side/:side', (req, res) ->
      console.log "post statement side"
      id=req.params.id
      side=req.params.side
      title=req.body.point
      return res.send {error:"no title specified!"} unless title
      Statement.get id, (err,stmt) ->
        return res.status(404).send {error:err} if err
        Statement.create {title: title}, (err,point)->
          return res.status(500).send {error:err} if err
          point.argue stmt, side, (err)->
            return res.status(201).send {id:point.id}

    @app.post url_prefix+'/statement/:id/side/:side/vote/:point', (req, res) ->
      ###### FIX ME #####
      user_data=
        name: "Tobias Hönisch"
        email: "tobias@hoenisch.at"
        password: "ultrasafepassword"
      User.create user_data, (err, user)->
      ####################

        console.log "post vote"
        id=req.params.id
        point_id=req.params.point
        side=req.params.side
        vote=req.body.vote
        return res.status(400).send {error:"no vote specified!"} unless vote==-1 or vote==1
        async.map [id, point_id], (item,callback)->
          Statement.get item, callback
        , (err, [stmt, point]) ->
          return res.status(404).send {error:err} if err
          user.vote stmt, point, side, vote, (err,total_votes)->
            return res.status(500).send {error:err} if err
            return res.status(200).send {votes:total_votes}


# Socket IO
    @io = require('socket.io').listen @app
    count = 0
    @io.sockets.on 'connection', (socket) =>
      count++
      console.log 'user connected ' + count
      socket.emit 'count', { number: count }
      socket.broadcast.emit 'count', { number: count }

      socket.on 'disconnect', () =>
        count--
        console.log 'user disconnected '
        socket.broadcast.emit 'count', { number: count }
    callback()

  stop: (callback) ->
    @io.server.close()
    callback()

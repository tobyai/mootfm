should=require 'should'
async = require "async"
Statement = require "../models/statement"

DatabaseHelper = require "../models/db-helper"

describe "Statement:", ->
  helper = new DatabaseHelper "http://localhost:7474"

  beforeEach (done) ->
    helper.delete_all_nodes done

  it "create statement", (done)->
    statement_data=
      title: "Apple is crap"
    Statement.create statement_data, (err,statement)->
      return done(err) if err
      statement.exists.should.be.true
      statement.title.should.eql "Apple is crap"
      done()

  it "delete statement", (done)->
    statement_data=
      title: "Apple is crap"
    Statement.create statement_data, (err,statement)->
      return done(err) if err
      statement.del (err)->
        return done(err) if err
        statement.exists.should.be.false
        done()

  it "get statement", (done)->
    statement_data=
      title: "Apple is crap"
    Statement.create statement_data, (err,create_statement)->
      return done(err) if err
      create_statement.exists.should.be.true
      Statement.get create_statement.id, (err,get_statement)->
        get_statement.should.eql create_statement
        get_statement.title.should.eql "Apple is crap"
        done()

  it "save statement", (done)->
    statement_data=
      title: "Apple is crap"
    Statement.create statement_data, (err,create_statement)->
      return done(err) if err
      create_statement.title = "Facebook IPO was awesome"
      create_statement.save (err)->
        return done(err) if err
        Statement.get create_statement.id, (err,get_statement)->
          get_statement.should.eql create_statement
          get_statement.title.should.eql "Facebook IPO was awesome"
          done()

  it "retrieve non existant statement", (done)->
    Statement.get 999999, (err)->
      should.exist(err)
      done()

  it "retrieve deleted statement", (done)->
    statement_data=
      title: "Apple is crap"
    Statement.create statement_data, (err,statement)->
      return done(err) if err
      statement.exists.should.be.true
      id=statement.id
      statement.del (err)->
        return done(err) if err
        statement.exists.should.be.false
        Statement.get id, (err)->
          should.exist(err)
          done()

  it "argue", (done)->
    statement_data=
      title: "Apple is crap"
    pro_statement_data=
      title: "Apple has child labour in China"
    async.map [statement_data, pro_statement_data ], (item,callback)->
      Statement.create item, callback
    , (err, [statement, pro_statement ]) ->
      return done(err) if err
      pro_statement.argue statement, "pro", (err)->
        statement.getArguments (err, all_arguments)->
          return done(err) if err
          all_arguments.should.have.ownProperty "pro"
          all_arguments["pro"][0].title.should.equal "Apple has child labour in China"
          done()

  it "unargue", (done)->
    statement_data=
      title: "Apple is crap"
    pro_statement_data=
      title: "Apple has child labour in China"
    async.map [statement_data, pro_statement_data ], (item,callback)->
      Statement.create item, callback
    , (err, [statement, pro_statement ]) ->
      return done(err) if err
      pro_statement.argue statement, "pro", (err)->
        pro_statement.unargue statement, "pro", (err)->
          statement.getArguments (err, all_arguments)->
            return done(err) if err
            all_arguments.should.eql {}
            done()

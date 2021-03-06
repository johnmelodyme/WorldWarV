'use strict'

http    = require 'http'
Primus  = require 'primus'
_       = require 'lodash'

SERVER_PORT = 8080

WWVEvents = {
  CREATE_ROOM: 'create room',
  ROOM_CREATED: 'room created',
  ROOM_CREATE_FAILED: 'room create failed',

  JOIN_ROOM: 'join room',
  ROOM_JOINED: 'room joined',
  ROOM_JOIN_FAILED: 'room join failed',

  SET_ALIAS: 'set alias',
  ALIAS_SET: 'alias set',

  LEAVE_ROOM: 'leave room',
  ROOM_LEFT: 'left room',
  LEAVE_ROOM_ERROR: 'leave room error',

  GET_USER: 'get user',
  USER: 'send user',

  ROOM_UPDATED: 'room updated',
  USER_NUKE: 'user nuke',
  BLOW_SHIT_UP: 'blow shit up'
}

users = {}
rooms = {}

# this is used to remove the circular refs caused
# by a room having users and a user having a room
summerizeUser = (user, teamNumber) ->
  id: user.id
  alias: user.alias
  teamNumber: teamNumber

module.exports = -> # main

  server = http.createServer()
  primus = new Primus server, {
    # config options go here
  }
  primus.use('emit', require('primus-emit'))

  # save the client side library
  primus.save "client/primus.js"

  # a new connection has been recieved
  primus.on 'connection', (spark) ->
    console.log "Connection recieved from #{spark.id}"

    # initialise a new user
    user = users[spark.id] = {
      id: spark.id
      alias: spark.id
      spark: spark # keep so users may push to users
    }

    # --------------------
    # define our routing

    # sets the alias field of the users
    spark.on WWVEvents.SET_ALIAS, (data) ->
      user.alias = data.alias # set the users alias
      spark.emit(WWVEvents.ALIAS_SET, user)

    # creates a room and ads the user that created
    # the room to the room.
    spark.on WWVEvents.CREATE_ROOM, (data) ->
      # ensure the room name isn't already taken
      if data.name not of rooms
        user.teamNumber = 0
        user.room = room = rooms[data.name] = { # create the room
          name: data.name
          users: [summerizeUser(user, 0)]

          map: data.map
          clouds: data.clouds
          atr: data.atr
        }
        # emit an event stating the room has been created
        spark.emit(WWVEvents.ROOM_CREATED, room)
      else
        spark.emit(WWVEvents.ROOM_CREATE_FAILED, {
          message: "#{data.name} is already taken."
        })

    # ads a user to a room and notifies all users in
    # the room the new user has joined the room
    spark.on WWVEvents.JOIN_ROOM, (data) ->
      # if the room exists
      #console.log data.name of rooms
      #console.log ((summerizeUser(user) not in rooms[data.name].users))

      if data.name of rooms and (summerizeUser(user, rooms[data.name].users.length) not in rooms[data.name].users)
        user.room = room = rooms[data.name] # room joining

        user.teamNumber = room.users.length
        room.users.push(summerizeUser(user, room.users.length))
        room.users.forEach (roomUser) -> # push current state of room
          if roomUser.id != spark.id
            #console.log users[roomUser.id]
            users[roomUser.id].spark.emit(WWVEvents.ROOM_UPDATED, {
              teamNumber: user.teamNumber
              room: room
            })
        # inform the requesting user they have joined the room
        spark.emit(WWVEvents.ROOM_JOINED, {
          teamNumber: user.teamNumber
          room: room
        })
      else
        spark.emit(WWVEvents.ROOM_JOIN_FAILED, {
          message: "#{data.name} is not a valid room."
        })

    # leave the room the user is currently in
    spark.on WWVEvents.LEAVE_ROOM, (data) ->
      #console.log "Leave room"

      if user.room
        room = user.room
        # remove the user from the list of users in the room
        _.remove room.users, (roomUser) -> roomUser.id == spark.id

        index = room.users.indexOf(summerizeUser(user))
        room.users.splice(index, 1) if index > -1
        # push the updated state of the room to remaining users
        if room.users.length > 0
          room.users.forEach (roomUser) -> # push current state of room
            users[roomUser.id].spark.emit(WWVEvents.ROOM_UPDATED, room)
        else # the room is empty
          delete rooms[room.name]
        # remove the users room
        delete user.room
        # inform the requesting user they have left the room
        spark.emit(WWVEvents.ROOM_LEFT)
      else
        # the users was not a member of a room
        spark.emit(WWVEvents.LEAVE_ROOM_ERROR, {
          message: 'User does not currently belong to a room'
        })

    # client requesting current user data
    spark.on WWVEvents.GET_USER, ->
      console.log 'GET_USER'
      spark.emit WWVEvents.USER, user

    spark.on WWVEvents.USER_NUKE, (data) ->
      user.room.nukes = user.room.nukes || []
      user.room.nukes.push(data.nuke)

      if data.exData
        user.room.exData = data.exData

      if user.room.nukes.length == user.room.users.length
        user.room.users.forEach (roomUser) ->
          users[roomUser.id].spark.emit(WWVEvents.BLOW_SHIT_UP, {
            nukes: user.room.nukes,
            exData: user.room.exData
          })
        delete user.room.nukes

  # handle disconnect
  primus.on 'disconnection', (spark) ->
    room = users[spark.id].room
    delete users[spark.id]

  server.listen SERVER_PORT, ->
    console.log "World War V has begun on port #{SERVER_PORT} >:o)"

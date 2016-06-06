/* global angular, Chess, Chessboard, ChessUtils */
import {Chess as SoliChess} from '../../contract/Chess.sol';
angular.module('dappChess').controller('PlayGameCtrl',
  function (games, $route, $scope, $rootScope) {
    // init chess validation
    var chess, board;


    function checkOpenGame(gameId) {
      return games.openGames.indexOf(gameId) !== -1;
    }

    // Update game information to user
    function updateGameInfo(status) {
      $('#info-status').html(status);
      $('#info-fen').html(chess.fen());
      $('#info-pgn').html(chess.pgn());
    }

    function processChessMove() {
      console.log('chessMove');

      let nextPlayer, status,
        game = $scope.getGame(),
        userColor = (game.self.color === 'white') ? 'w' :  'b';

      // define next player
      if (userColor === chess.turn()) {
        nextPlayer = game.self.username;

        //chess.enableUserInput(false);
      } else {
        nextPlayer = game.opponent.username;
        //chess.enableUserInput(true);
      }

      // game over?
      if (chess.in_checkmate() === true) { // jshint ignore:line
        status = 'CHECKMATE! ' + nextPlayer + ' lost.';
      }

      // draw?
      else if (chess.in_draw() === true) { // jshint ignore:line
        status = 'DRAW!';
      }

      // game is still on
      else {
        status = 'Next player is ' + nextPlayer + '.';

        // plaver in check?
        if (chess.in_check() === true) { // jshint ignore:line
          status = 'CHECK! ' + status;
          // ToDo: set 'danger' color for king
          console.log('css');
        }
      }

      updateGameInfo(status);
    }

    // player clicked on chess piece
    function pieceSelected(notationSquare) {
      var i,
        movesNotation,
        movesPosition = [];

      movesNotation = chess.moves({square: notationSquare, verbose: true});
      for (i = 0; i < movesNotation.length; i++) {
        movesPosition.push(ChessUtils.convertNotationSquareToIndex(movesNotation[i].to));
      }
      return movesPosition;
    }

    // move chess piece if valid
    function pieceMove(move) {
      let game = $scope.getGame();

      try {
        $rootScope.$broadcast('message', 'Submitting your move, please wait a moment...',
          'loading', 'playgame-' + game.gameId);
        $rootScope.$apply();

        SoliChess.move(game.gameId, '96', '80', {from: game.self.accountId});

        SoliChess.Move({}, function(err, data) {
          console.log('eventMove', err, data);
          if(err) {

          }
          else {
            // if valid: move chess piece from a to b
            // else: return null

            console.log(chess.fen());
            chess.move({
              from: move.from,
              to: move.to,
              promotion: 'q'
            });

            console.log(chess.fen());
            board.setPosition(chess.fen());
            board.reset();

            let nextPlayer, status,
              game = $scope.getGame(),
              userColor = (game.self.color === 'white') ? 'w' :  'b';

            // define next player
            if (userColor === chess.turn()) {
              nextPlayer = game.self.username;

              //chess.enableUserInput(false);
            } else {
              nextPlayer = game.opponent.username;
              //chess.enableUserInput(true);
            }

            // game over?
            if (chess.in_checkmate() === true) { // jshint ignore:line
              status = 'CHECKMATE! ' + nextPlayer + ' lost.';
            }

            // draw?
            else if (chess.in_draw() === true) { // jshint ignore:line
              status = 'DRAW!';
            }

            // game is still on
            else {
              status = 'Next player is ' + nextPlayer + '.';

              // plaver in check?
              if (chess.in_check() === true) { // jshint ignore:line
                status = 'CHECK! ' + status;
                // ToDo: set 'danger' color for king
                console.log('css');
              }
            }

            updateGameInfo(status);

            $rootScope.$broadcast('message',
              'Your move has been accepted',
              'success', 'playgame-' + game.gameId);
            $rootScope.$apply();
          }
        });

      } catch(e) {
        $rootScope.$broadcast('message', 'Could not validate your move',
          'error', 'playgame-' + game.gameId);
        $rootScope.$apply();
      }
      return chess.fen();

    }

    // set all chess pieces in start position
    function resetGame(board) {
      console.log('resetGame', board);

      let game = $scope.getGame();
      board.setPosition(ChessUtils.FEN.startId);
      chess.reset();

      let gamer;
      if (game.self.color === 'white') {
        gamer = game.self.username;
      } else {
        gamer = game.opponent.username;
      }

      updateGameInfo('Next player is ' + gamer + '.' );
    }

    $scope.getGameId = function() {
      return $route.current.params.id;
    };
    $scope.isOpenGame = function() {
      let gameId = $scope.getGameId();

      if(gameId) {
        return checkOpenGame(gameId);
      }

      return false;
    };
    $scope.getGame = function() {
      let gameId = $scope.getGameId();

      if(gameId) {
        return games.getGame(gameId);
      }

      return false;
    };
    $scope.surrender = function() {
      $rootScope.$broadcast('message', 'Submitting your surrender, please wait...',
        'loading', 'playgame');
      try {
        console.log('calling Chess.surrender(' + $scope.getGameId() + ')');
        Chess.surrender($scope.getGameId(), {from: $scope.getGame().self.accountId});
      }
      catch(e) {
        $rootScope.$broadcast('message', 'Could not submit your surrender', 'loading', 'playgame');
      }
    };

    $scope.gameIsWon = function() {
      let game = $scope.getGame();
      return typeof(game.winner) !== 'undefined' && game.winner === 'self';
    };

    $scope.gameIsLost = function() {
      let game = $scope.getGame();
      return typeof(game.winner) !== 'undefined' && game.winner === 'opponent';
    };

    $scope.gameIsActive = function() {
      return typeof($scope.getGame().winner) === 'undefined';
    };

    //--- init Chessboard ---
    if ($scope.isOpenGame !== false) {
      $(document).ready(function () {
        chess = new Chess();

        let game = $scope.getGame();

        board = new Chessboard('my-board', {
            position: ChessUtils.FEN.startId,
            eventHandlers: {
              onPieceSelected: pieceSelected,
              onMove: pieceMove
            }
          }
        );

        // init game
        resetGame(board);

        // opponent starts game
        if (game.self.color === 'black') {
          board.setOrientation(ChessUtils.ORIENTATION.black);
          board.enableUserInput(false);
        }

      });
    }
  }
);

/**
 * Chess contract
 * Stores any amount of games with two players and current state.
 * State encoding:
 *    positive numbers for white, negative numbers for black
 *    for details, see
 *    https://github.com/ise-ethereum/on-chain-chess/wiki/Chess-board-representation
 */

import "TurnBasedGame.sol";
import "ChessLogic.sol";
import "Auth.sol";

contract Chess is TurnBasedGame, Auth {
    using ChessLogic for ChessLogic.State;
    mapping (bytes32 => ChessLogic.State) gameStates;



    event GameInitialized(bytes32 indexed gameId, address indexed player1, string player1Alias, address playerWhite, uint pot);
    event GameJoined(bytes32 indexed gameId, address indexed player1, string player1Alias, address indexed player2, string player2Alias, address playerWhite, uint pot);
    event GameStateChanged(bytes32 indexed gameId, int8[128] state);
    event GameTimeoutStarted(bytes32 indexed gameId,uint timeoutStarted, int8 timeoutState);
    // GameDrawOfferRejected: notification that a draw of the currently turning player
    //                        is rejected by the waiting player
    event GameDrawOfferRejected(bytes32 indexed gameId);
    event Move(bytes32 indexed gameId, address indexed player, uint256 fromIndex, uint256 toIndex);

    function Chess(bool enableDebugging) TurnBasedGame(enableDebugging) {
    }

    /**
     * Initialize a new game
     * string player1Alias: Alias of the player creating the game
     * bool playAsWhite: Pass true or false depending on if the creator will play as white
     */
    function initGame(string player1Alias, bool playAsWhite) public returns (bytes32) {
        bytes32 gameId = super.initGame(player1Alias, playAsWhite);

        // Setup game state
        int8 nextPlayerColor = int8(1);
        gameStates[gameId].setupState(nextPlayerColor);
        if (playAsWhite) {
            // Player 1 will play as white
            gameStates[gameId].playerWhite = msg.sender;

            // Game starts with White, so here player 1
            games[gameId].nextPlayer = games[gameId].player1;
        }

        // Sent notification events
        GameInitialized(gameId, games[gameId].player1, player1Alias, gameStates[gameId].playerWhite, games[gameId].pot);
        GameStateChanged(gameId, gameStates[gameId].fields);
        return gameId;
    }

    /**
     * Join an initialized game
     * bytes32 gameId: ID of the game to join
     * string player2Alias: Alias of the player that is joining
     */
    function joinGame(bytes32 gameId, string player2Alias) public {
        super.joinGame(gameId, player2Alias);

        // If the other player isn't white, player2 will play as white
        if (gameStates[gameId].playerWhite == 0) {
            gameStates[gameId].playerWhite = msg.sender;
            // Game starts with White, so here player2
            games[gameId].nextPlayer = games[gameId].player2;
        }

        GameJoined(gameId, games[gameId].player1, games[gameId].player1Alias, games[gameId].player2, player2Alias, gameStates[gameId].playerWhite, games[gameId].pot);
    }

    /**
    *
    * verify signature of state
    * verify signature of move
    * apply state, verify move
    */
    function moveFromState(bytes32 gameId, int8[128] state, uint256 fromIndex,
                           uint256 toIndex, bytes sigState) notEnded(gameId) public {
        // check whether sender is a member of this game
        if (games[gameId].player1 != msg.sender && games[gameId].player2 != msg.sender) {
            throw;
        }

        // find opponent to msg.sender
        address opponent;
        if (msg.sender == games[gameId].player1) {
            opponent = games[gameId].player2;
        } else {
            opponent = games[gameId].player1;
        }

        // verify state - should be signed by the other member of game - not mover
        if (!verifySig(opponent, sha3(state), sigState)) {
            throw;
        }

        // check move count. New state should have a higher move count.
        if ((state[8] * int8(128) + state[9]) < (gameStates[gameId].fields[8] * int8(128) + gameStates[gameId].fields[9])) {
            throw;
        }

        int8 playerColor = msg.sender == gameStates[gameId].playerWhite ? int8(1) : int8(-1);

        // apply state
        gameStates[gameId].setState(state, playerColor);
        games[gameId].nextPlayer =  msg.sender;

        // apply and verify move
        move(gameId, fromIndex, toIndex);
    }

    function move(bytes32 gameId, uint256 fromIndex, uint256 toIndex) notEnded(gameId) public {
        if (games[gameId].nextPlayer != msg.sender) {
            throw;
        }
        if(games[gameId].timeoutState != 0) {
            games[gameId].timeoutState = 0;
        }
        // Chess move validation
        gameStates[gameId].move(fromIndex, toIndex);

        // Set nextPlayer
        if (msg.sender == games[gameId].player1) {
            games[gameId].nextPlayer = games[gameId].player2;
        } else {
            games[gameId].nextPlayer = games[gameId].player1;
        }

        // Send events
        Move(gameId, msg.sender, fromIndex, toIndex);
        GameStateChanged(gameId, gameStates[gameId].fields);
    }

    /* Explicit set game state. Only in debug mode */
    function setGameState(bytes32 gameId, int8[128] state, address nextPlayer) debugOnly public {
        int8 playerColor = nextPlayer == gameStates[gameId].playerWhite ? int8(1) : int8(-1);
        gameStates[gameId].setState(state, playerColor);
        games[gameId].nextPlayer = nextPlayer;
        GameStateChanged(gameId, gameStates[gameId].fields);
    }

    function getCurrentGameState(bytes32 gameId) constant returns (int8[128]) {
       return gameStates[gameId].fields;
    }

    function getWhitePlayer(bytes32 gameId) constant returns (address) {
       return gameStates[gameId].playerWhite;
    }

    /* The sender claims he has won the game. Starts a timeout. */
    function claimWin(bytes32 gameId) notEnded(gameId) public {

        var game = games[gameId];
        // just the two players currently playing
        if (msg.sender != game.player1 && msg.sender != game.player2)
            throw;
        // only if timeout has not started
        if (game.timeoutState != 0)
            throw;
        // you can only claim draw / victory in the enemies turn
        if (msg.sender == game.nextPlayer)
            throw;
        // get the color of the player that wants to claim win
        int8 otherPlayerColor = gameStates[gameId].playerWhite == msg.sender ? int8(-1) : int8(1);
        // the one not sending is white -> the sending player is Black

        // We get the king position of that player
        uint256 kingIndex = uint256(gameStates[gameId].getOwnKing(otherPlayerColor));
        // if he is in check the request is legal
        if (gameStates[gameId].checkForCheck(kingIndex, otherPlayerColor)){
            game.timeoutStarted = now;
            game.timeoutState = 1;
            GameTimeoutStarted(gameId, game.timeoutStarted, game.timeoutState);
        // else it is not
        } else {
            throw;
        }


    }

    /* The sender offers the other player a draw. Starts a timeout. */
    function offerDraw(bytes32 gameId) notEnded(gameId) public {
        var game = games[gameId];
        // just the two players currently playing
        if (msg.sender != game.player1 && msg.sender != game.player2)
            throw;
        // only if timeout has not started
        if (game.timeoutState != 0)
            throw;

        game.timeoutStarted = now;
        if (msg.sender == game.nextPlayer) {
            game.timeoutState = -2;
        } else {
            game.timeoutState = -1;
        }
        GameTimeoutStarted(gameId, game.timeoutStarted, game.timeoutState);
    }

    /*
     * The sender (currently turning player) offers the other player (waiting)
     * a draw. Starts a timeout.
     */
    function rejectCurrentPlayerDraw(bytes32 gameId) notEnded(gameId) public {
        var game = games[gameId];
        // just the two players currently playing
        if (msg.sender != game.player1 && msg.sender != game.player2)
            throw;
        // only if timeout is present
        if (game.timeoutState != -2)
            throw;
        // only not playing player is able to reject a draw offer of the nextPlayer
        if (msg.sender == game.nextPlayer)
            throw;
        game.timeoutState = 0;
        GameDrawOfferRejected(gameId);
    }

    /*
     * The sender claims that the other player is not in the game anymore.
     * Starts a Timeout that can be claimed
     */
    function claimTimeout(bytes32 gameId) notEnded(gameId) public {
        var game = games[gameId];
        // just the two players currently playing
        if (msg.sender != game.player1 && msg.sender != game.player2)
            throw;
        // only if timeout has not started
        if (game.timeoutState != 0)
            throw;
        // you can only claim draw / victory in the enemies turn
        if (msg.sender == game.nextPlayer)
            throw;
        game.timeoutStarted = now;
        game.timeoutState = 2;
        GameTimeoutStarted(gameId, game.timeoutStarted, game.timeoutState);
    }

    /*
     * The sender rejects the previously claimed timeout of the other player.
     * This will NOT reset the timeout.
     * Timeout will 'degrade' to a draw timeout.
     */
    function rejectTimeout(bytes32 gameId) notEnded(gameId) public {
        var game = games[gameId];
        // just the two players currently playing
        if (msg.sender != game.player1 && msg.sender != game.player2)
            throw;
        // only if timeout has not started
        if (game.timeoutState != 2)
            throw;
        // you can only reject a timeout if you are the next player
        if (msg.sender != game.nextPlayer)
            throw;
        game.timeoutState = 1;
        GameTimeoutStarted(gameId, game.timeoutStarted, game.timeoutState);
    }

    /* The sender claims a previously started timeout. */
    function claimTimeoutEnded(bytes32 gameId) notEnded(gameId) public {
        var game = games[gameId];
        // just the two players currently playing
        if (msg.sender != game.player1 && msg.sender != game.player2)
            throw;
        if (game.timeoutState == 0)
            throw;
        if (now < game.timeoutStarted + 10 minutes)
            throw;
        if (msg.sender == game.nextPlayer) {
            if (game.timeoutState == -2) { // draw
                game.ended = true;
                games[gameId].player1Winnings = games[gameId].pot / 2;
                games[gameId].player2Winnings = games[gameId].pot / 2;
                games[gameId].pot = 0;
                GameEnded(gameId);
            } else {
                throw;
            }
        } else {
            // Game is a draw, transfer ether back
            if (game.timeoutState == -1) {
                game.ended = true;
                games[gameId].player1Winnings = games[gameId].pot / 2;
                games[gameId].player2Winnings = games[gameId].pot / 2;
                games[gameId].pot = 0;
                GameEnded(gameId);
            } else if (game.timeoutState == 1 || game.timeoutState == 2){
                game.ended = true;
                game.winner = msg.sender;
                if(msg.sender == game.player1) {
                    games[gameId].player1Winnings = games[gameId].pot;
                    games[gameId].pot = 0;
                } else {
                    games[gameId].player2Winnings = games[gameId].pot;
                    games[gameId].pot = 0;
                }
                GameEnded(gameId);
            } else {
                throw;
            }
        }
    }

    /* A timeout can be confirmed by the non-initializing player. */
    function confirmGameEnded(bytes32 gameId) notEnded(gameId) public {
        var game = games[gameId];
        // just the two players currently playing
        if (msg.sender != game.player1 && msg.sender != game.player2)
            throw;
        if (game.timeoutState == 0)
            throw;
        if (msg.sender != game.nextPlayer) {
            if (game.timeoutState == -2) { // draw
                game.ended = true;
                games[gameId].player1Winnings = games[gameId].pot / 2;
                games[gameId].player2Winnings = games[gameId].pot / 2;
                games[gameId].pot = 0;
                GameEnded(gameId);
            } else {
                throw;
            }
        } else {
            // Game is a draw, transfer ether back
            if (game.timeoutState == -1) {
                game.ended = true;
                games[gameId].player1Winnings = games[gameId].pot / 2;
                games[gameId].player2Winnings = games[gameId].pot / 2;
                games[gameId].pot = 0;
                GameEnded(gameId);
            } else if (game.timeoutState == 1 || game.timeoutState == 2) {
                // TODO: do we want to allow this for timeoutState == 2 ?
                game.ended = true;
                // other player won
                if(msg.sender == game.player1) {
                    game.winner = game.player2;
                    games[gameId].player2Winnings = games[gameId].pot;
                    games[gameId].pot = 0;
                } else {
                    game.winner = game.player1;
                    games[gameId].player1Winnings = games[gameId].pot;
                    games[gameId].pot = 0;
                }
                GameEnded(gameId);
            } else {
                throw;
            }
        }
    }

    /* This unnamed function is called whenever someone tries to send ether to the contract */
    function () {
        throw; // Prevents accidental sending of ether
    }
}

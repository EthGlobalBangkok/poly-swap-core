# PolySwap smart order

The smart contracts and scripts to place orders (on CoW Swap) that wait a polymarket result

## Usage

npm i
create .env file with the var PRIVATE_KEY=your_private_key
npm run deploy
change the ORDER_FACTORY address in placeOrder.js by the one generated by the deploy script
npm run place-order

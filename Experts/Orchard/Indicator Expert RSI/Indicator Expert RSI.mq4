/*
   RSI Expert
   Copyright 2023, Orchard Forex
   https://www.orchardforex.com

   A very simple expert just using overbought / oversold
   levels to show how to write an expert using a single
   indicator.

   This not a recommended strategy, it is just for demonstration

*/

#property strict

#property copyright "Copyright 2023, Orchard Forex"
#property link "https://www.orchardforex.com"
#property version "1.00"

//
// enums - see earlier videos
//
enum ENUM_RISK_TYPE {
   RISK_TYPE_FIXED_LOTS,     // Fixed lots
   RISK_TYPE_EQUITY_PERCENT, // Percent of equity
};

//
//	Inputs
//

// RSI Settings
input int                InpRSIPeriod       = 14;          // RSI Period
input ENUM_APPLIED_PRICE InpRSIAppliedPrice = PRICE_CLOSE; // RSI Price
input double             InpRSIOverbought   = 70.0;        // Overbought level
input double             InpRSIOversold     = 30.0;        // Oversold level

// Take profit stop loss
input double             InpStopLossPips    = 10.0; // Stop loss pips
input double             InpTakeProfitPips  = 10.0; // Take profit pips

// Standard features
input int                InpMagic           = 232323;               // Magic number
input string             InpTradeComment    = "RSI Levels";         // Trade comment
input double             InpRisk            = 0.1;                  // Risk
input ENUM_RISK_TYPE     InpRiskType        = RISK_TYPE_FIXED_LOTS; // Risk type

// Globals
double                   StopLoss;
double                   TakeProfit;

; // just because my auto formatter needs it
int OnInit() {

   // Check inputs
   if ( !ValidateInputs() ) return INIT_PARAMETERS_INCORRECT;

   // Gloabl settings
   StopLoss   = PipsToDouble( InpStopLossPips );
   TakeProfit = PipsToDouble( InpTakeProfitPips );

   return INIT_SUCCEEDED;
}

void OnDeinit( const int reason ) {}

void OnTick() {

   // Only trade on candle close
   if ( !IsNewBar() ) return;

   double rsiValues[]; // to hold values from bars 1 and 2
   // I'm also getting bar 0, just because it keeps the array in line with chart;
   if ( !GetRSIValues( rsiValues ) ) return; // in case of a problem getting the rsi

   // Get count of open positions for this expert
   int positionCount[];
   CountPositions( Symbol(), InpMagic, positionCount );

   // Process any close, if RSI goes into opposite territory before SLTP
   if ( positionCount[ORDER_TYPE_BUY] > 0 && rsiValues[1] >= InpRSIOverbought ) CloseAll( Symbol(), InpMagic, ORDER_TYPE_BUY );
   if ( positionCount[ORDER_TYPE_SELL] > 0 && rsiValues[1] <= InpRSIOversold ) CloseAll( Symbol(), InpMagic, ORDER_TYPE_SELL );

   // Open new positions if none already open
   if ( positionCount[ORDER_TYPE_BUY] == 0 && rsiValues[2] <= InpRSIOversold && rsiValues[1] > InpRSIOversold ) {
      OpenPosition( ORDER_TYPE_BUY );
   }
   if ( positionCount[ORDER_TYPE_SELL] == 0 && rsiValues[2] >= InpRSIOverbought && rsiValues[1] < InpRSIOverbought ) {
      OpenPosition( ORDER_TYPE_SELL );
   }
}

//
//	Init functions
//

// ValidateInputs
bool ValidateInputs() {

   bool success = true;

   if ( InpRSIPeriod < 1 ) {
      Alert( "RSI Period must be >= 1" );
      success = false;
   }

   if ( InpStopLossPips < 0 ) {
      Alert( "Stop Loss Pips must be >= 0" );
      success = false;
   }

   if ( InpTakeProfitPips < 0 ) {
      Alert( "Take Profit Pips must be >= 0" );
      success = false;
   }

   if ( InpRisk <= 0 ) {
      Alert( "Risk must be > 0" );
      success = false;
   }

   return success;
}

//
// Indicator functions
//
bool GetRSIValues( double &rsiValues[] ) {

   // This is running on the chart symbol/timeframe so everything should be up to date
   // define some vars, for readability
   int bufferNumber = 0; // RSI only has one buffer
   int startPos     = 0; // from bar 0, not needed but no harm
   int count        = 3; // get 3 values back

   // Make room for the data
   ArrayResize( rsiValues, count );
   for ( int i = 0; i < count; i++ ) {
      rsiValues[i] = iRSI( Symbol(), Period(), InpRSIPeriod, InpRSIAppliedPrice, i );
   }
   return true;
}

//
//	Position functions
//
int CountPositions( string symbol, long magic, int &positionCount[] ) {

   ArrayResize( positionCount, 2 );
   ArrayInitialize( positionCount, 0 );
   for ( int i = OrdersTotal() - 1; i >= 0; i-- ) {
      if ( !OrderSelectByIndex( i, symbol, magic ) ) continue;
      positionCount[OrderType()]++;
   }
   return ( positionCount[0] + positionCount[1] );
}

bool OrderSelectByIndex( int index, string symbol, long magic ) {

   if ( !OrderSelect( index, SELECT_BY_POS, MODE_TRADES ) ) return false;
   if ( OrderSymbol() != symbol ) return false;
   if ( OrderMagicNumber() != magic ) return false;
   if ( OrderType() != ORDER_TYPE_BUY && OrderType() != ORDER_TYPE_SELL ) return false;
   return true;
}

//
// Trading functions
//
bool CloseAll( string symbol, long magic, ENUM_ORDER_TYPE type ) {

   bool success = true;
   for ( int i = OrdersTotal() - 1; i >= 0; i-- ) {
      if ( !OrderSelectByIndex( i, symbol, magic ) ) continue;
      if ( OrderType() != type ) continue;

      success &= OrderClose( OrderTicket(), OrderLots(), OrderClosePrice(), 0 );
   }
   return success;
}

bool OpenPosition( ENUM_ORDER_TYPE type ) {

   double  price   = 0;
   double  slPrice = 0;
   double  tpPrice = 0;

   // Get latest tick to make sure information is fresh
   MqlTick tick;
   if ( !SymbolInfoTick( Symbol(), tick ) ) return false; // no current data

                                                          // Set price values based on type
   if ( type == ORDER_TYPE_BUY ) {
      price   = tick.ask;
      slPrice = price - StopLoss;
      tpPrice = price + TakeProfit;
   }
   else {
      price   = tick.bid;
      slPrice = price + StopLoss;
      tpPrice = price - TakeProfit;
   }

   // Normalise prices
   price         = NormalizeDouble( price, Digits() );
   slPrice       = NormalizeDouble( slPrice, Digits() );
   tpPrice       = NormalizeDouble( tpPrice, Digits() );

   double volume = GetVolume( InpRiskType, InpRisk, StopLoss );

   int    ticket = OrderSend( Symbol(), type, volume, price, 0, slPrice, tpPrice, InpTradeComment, InpMagic );
   if ( ticket <= 0 ) {
      PrintFormat( "Error opening trade on %s, type=%s, volume=%f, price=%f, sl=%f, tp=%f", Symbol(), EnumToString( type ), volume, price, slPrice, tpPrice );
   }
   return ( ticket > 0 );
}

// Volume
double GetVolume( ENUM_RISK_TYPE riskType, double risk, double loss ) {

   if ( riskType == RISK_TYPE_FIXED_LOTS ) return NormaliseVolume( risk );
   if ( riskType == RISK_TYPE_EQUITY_PERCENT ) return NormaliseVolume( GetVolumeEquityPercent( risk, loss ) );
   return 0;
}

double GetVolumeEquityPercent( double risk, double loss ) {

   double equity     = AccountInfoDouble( ACCOUNT_EQUITY );
   double riskAmount = equity * risk / 100;                                   // risk in deposit currency

   double tickValue  = SymbolInfoDouble( Symbol(), SYMBOL_TRADE_TICK_VALUE ); // value of a tick in deposit currency
   double tickSize   = SymbolInfoDouble( Symbol(), SYMBOL_TRADE_TICK_SIZE );  // size of a tick price movement
   double lossTicks  = loss / tickSize;                                       // There may be rounding here, loss is in price movement

   double volume     = riskAmount / ( lossTicks * tickValue );

   return volume;
}

double NormaliseVolume( double volume ) {

   if ( volume <= 0 ) return 0; // nothing to do

   double max    = SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MAX );
   double min    = SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MIN );
   double step   = SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_STEP );

   double result = MathRound( volume / step ) * step;
   if ( result > max ) result = max;
   if ( result < min ) result = min;

   return result;
}

//
// General purpose functions
//
double PipsToDouble( double pips ) { return PipsToDouble( Symbol(), pips ); }

double PipsToDouble( string symbol, double pips ) {

   int digits = ( int )SymbolInfoInteger( symbol, SYMBOL_DIGITS );
   if ( digits == 3 || digits == 5 ) {
      pips = pips * 10;
   }
   double value = pips * SymbolInfoDouble( symbol, SYMBOL_POINT );
   return value;
}

bool IsNewBar() {
   static datetime currentTime = 0;
   return IsNewBar( Symbol(), ( ENUM_TIMEFRAMES )Period(), currentTime );
}

bool IsNewBar( string symbol, ENUM_TIMEFRAMES timeframe, datetime &currentTime ) {

   datetime now = iTime( symbol, timeframe, 0 );
   if ( currentTime == now ) return false;
   currentTime = now;
   return true;
}

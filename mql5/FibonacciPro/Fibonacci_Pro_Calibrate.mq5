// Fibonacci Pro Calibrate 1.66 -- for each Market Watch symbol, measures the money a 1.0
// price move makes on 1.00 lot with the terminal's own profit calculation. Fibonacci Pro's
// lot sizing uses these values instead of the broker's contract size and tick value.
// It sends no orders (OrderCalcProfit only calculates). No DLLs or network access.
// Install in MQL5/Scripts, compile with the current MetaEditor 5, then drop it on any chart.
#property copyright "Custom implementation for the user"
#property version   "1.66"
#property description "Measures the value of a 1.0 price move on 1.00 lot for each Market Watch symbol with the terminal's own profit calculation, for Fibonacci Pro's lot sizing. Sends no orders."
#property script_show_inputs
#property strict

input bool InpAllSymbols=true;   // All Market Watch symbols (false: only this chart's symbol)

// CALIB_IO_BEGIN -- the same text is in Fibonacci_Pro_Calibrate.mq5 (the build checks it)
#define FPC_MAGIC 1179668851
#define FPC_END 1179668859
#define FPC_SCHEMA 1
#define FPC_MAX 2000
#define FPC_TOL 0.02
// One calibrated symbol: the money a 1.0 price move makes on 1.00 lot, from the terminal's
// own profit calculation (OrderCalcProfit), measured by the calibration script.
struct FPCalib
  {
   string symbol,profit_ccy,account_ccy;
   double value_profit;        // profit currency per 1.0 price move per 1.00 lot (0: no rate to convert)
   double value_account;       // the same in the account currency, at the rate of the calibration
   double contract,tick_size,tick_value;  // the symbol's properties then (a changed contract voids it)
   long time;                  // server time of the calibration
  };
string FPCSafe(string value)
  {
   string forbidden="\\/:*?\"<>|\r\n\t";
   for(int i=0;i<StringLen(forbidden);i++)StringReplace(value,StringSubstr(forbidden,i,1),"_");
   return StringSubstr(value,0,80);
  }
// One file per trade server: every account and chart on that server shares it.
string FPCFile(){return "FibonacciPro\\"+FPCSafe(AccountInfoString(ACCOUNT_SERVER))+".calib";}
void FPCWText(const int f,const string text)
  {FileWriteInteger(f,StringLen(text),INT_VALUE);if(StringLen(text)>0)FileWriteString(f,text,StringLen(text));}
bool FPCRText(const int f,string &text,const int maxlen)
  {int n=FileReadInteger(f,INT_VALUE);if(n<0 || n>maxlen)return false;if(n==0){text="";return true;}text=FileReadString(f,n);return StringLen(text)==n;}
// Number of records, or -1 when the file is missing or damaged (nothing is half-read).
int FPCLoad(const string filename,FPCalib &list[])
  {
   ArrayResize(list,0);
   int f=FileOpen(filename,FILE_READ|FILE_BIN|FILE_UNICODE|FILE_SHARE_READ);
   if(f==INVALID_HANDLE)return -1;
   int n=0;
   bool good=FileReadInteger(f,INT_VALUE)==FPC_MAGIC && FileReadInteger(f,INT_VALUE)==FPC_SCHEMA;
   if(good){n=FileReadInteger(f,INT_VALUE);good=n>=0 && n<=FPC_MAX;}
   if(good)ArrayResize(list,n);
   for(int i=0;good && i<n;i++)
     {
      good=FPCRText(f,list[i].symbol,64) && FPCRText(f,list[i].profit_ccy,16) && FPCRText(f,list[i].account_ccy,16);
      if(!good)break;
      list[i].value_profit=FileReadDouble(f);list[i].value_account=FileReadDouble(f);
      list[i].contract=FileReadDouble(f);list[i].tick_size=FileReadDouble(f);list[i].tick_value=FileReadDouble(f);
      list[i].time=FileReadLong(f);
      good=MathIsValidNumber(list[i].value_profit) && MathIsValidNumber(list[i].value_account) && list[i].value_profit>=0 && list[i].value_account>0
           && MathIsValidNumber(list[i].contract) && MathIsValidNumber(list[i].tick_size) && MathIsValidNumber(list[i].tick_value);
     }
   if(good)good=FileReadInteger(f,INT_VALUE)==FPC_END && FileTell(f)==FileSize(f);
   FileClose(f);
   if(!good){ArrayResize(list,0);return -1;}
   return n;
  }
// Written to a temporary file, verified by reading it back, then swapped in (old copy kept as .bak).
bool FPCSave(const string filename,FPCalib &list[],const int n)
  {
   string temporary=filename+".tmp";
   int f=FileOpen(temporary,FILE_WRITE|FILE_BIN|FILE_UNICODE);
   if(f==INVALID_HANDLE)return false;
   ResetLastError();
   FileWriteInteger(f,FPC_MAGIC,INT_VALUE);FileWriteInteger(f,FPC_SCHEMA,INT_VALUE);FileWriteInteger(f,n,INT_VALUE);
   for(int i=0;i<n;i++)
     {
      FPCWText(f,list[i].symbol);FPCWText(f,list[i].profit_ccy);FPCWText(f,list[i].account_ccy);
      FileWriteDouble(f,list[i].value_profit);FileWriteDouble(f,list[i].value_account);
      FileWriteDouble(f,list[i].contract);FileWriteDouble(f,list[i].tick_size);FileWriteDouble(f,list[i].tick_value);
      FileWriteLong(f,list[i].time);
     }
   FileWriteInteger(f,FPC_END,INT_VALUE);FileFlush(f);int error=GetLastError();FileClose(f);
   FPCalib check[];
   if(error!=0 || FPCLoad(temporary,check)!=n)return false;
   if(FileIsExist(filename) && !FileCopy(filename,0,filename+".bak",FILE_REWRITE))return false;
   return FileMove(temporary,0,filename,FILE_REWRITE);
  }
int FPCFind(FPCalib &list[],const int n,const string symbol)
  {for(int i=0;i<n;i++)if(list[i].symbol==symbol)return i;return -1;}
// Calculation modes whose profit is (close - open) x contract size x lots, in the profit currency.
bool FPCContractMode(const long mode)
  {
   return mode==SYMBOL_CALC_MODE_FOREX || mode==SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE || mode==SYMBOL_CALC_MODE_CFD
          || mode==SYMBOL_CALC_MODE_CFDINDEX || mode==SYMBOL_CALC_MODE_CFDLEVERAGE
          || mode==SYMBOL_CALC_MODE_EXCH_STOCKS || mode==SYMBOL_CALC_MODE_EXCH_STOCKS_MOEX;
  }
// A symbol quoting one currency in the other: Market Watch first, forex symbols preferred.
// inverse: the symbol is `to` per `from`. A symbol found outside Market Watch is added to
// it, because the terminal only streams quotes for selected symbols.
bool FPCFindConv(const string from,const string to,string &sym,bool &inverse)
  {
   int best=-1;sym="";inverse=false;
   for(int pass=0;pass<2 && best<0;pass++)
     {
      bool selected=pass==0;
      int n=SymbolsTotal(selected);
      for(int i=0;i<n;i++)
        {
         string s=SymbolName(i,selected);
         string b=SymbolInfoString(s,SYMBOL_CURRENCY_BASE),p=SymbolInfoString(s,SYMBOL_CURRENCY_PROFIT);
         bool direct=b==from && p==to,inv=b==to && p==from;
         if(!direct && !inv)continue;
         long mode=SymbolInfoInteger(s,SYMBOL_TRADE_CALC_MODE);
         int score=(mode==SYMBOL_CALC_MODE_FOREX || mode==SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE)?2:1;
         if(SymbolInfoDouble(s,SYMBOL_BID)>0)score+=2;
         if(score>best){best=score;sym=s;inverse=inv;}
        }
     }
   if(best<0)return false;
   if(SymbolInfoInteger(sym,SYMBOL_SELECT)==0)SymbolSelect(sym,true);
   return true;
  }
// Units of `to` per unit of `from` (0: no symbol or no quote). key/sym/inv cache the search.
double FPCConv(const string from,const string to,string &key,string &sym,bool &inv)
  {
   if(from=="" || to=="")return 0;
   if(from==to)return 1.0;
   if(key!=from+">"+to){key=from+">"+to;FPCFindConv(from,to,sym,inv);}
   if(sym=="")return 0;
   double bid=SymbolInfoDouble(sym,SYMBOL_BID),ask=SymbolInfoDouble(sym,SYMBOL_ASK);
   if(inv)return ask>0?1.0/ask:0;
   return bid>0?bid:0;
  }
// Contract method: contract size x conversion to the account currency (0: not this kind of symbol).
double FPCContractValue(const string sym,const string acc,string &key,string &csym,bool &inv)
  {
   if(!FPCContractMode(SymbolInfoInteger(sym,SYMBOL_TRADE_CALC_MODE)))return 0;
   double contract=SymbolInfoDouble(sym,SYMBOL_TRADE_CONTRACT_SIZE);
   if(!(contract>0))return 0;
   double conv=FPCConv(SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT),acc,key,csym,inv);
   return conv>0?contract*conv:0;
  }
// Tick-value method: the broker's tick value for a losing position / tick size.
double FPCTickValue(const string sym)
  {
   double size=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE),value=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(!(value>0))value=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   return size>0 && value>0?value/size:0;
  }
// CALIB_IO_END

string CalNum(const double v,const int digits)
  {
   string s=DoubleToString(v,digits);
   if(StringFind(s,".")>=0)
     {
      while(StringLen(s)>0 && StringSubstr(s,StringLen(s)-1)=="0")s=StringSubstr(s,0,StringLen(s)-1);
      if(StringLen(s)>0 && StringSubstr(s,StringLen(s)-1)==".")s=StringSubstr(s,0,StringLen(s)-1);
     }
   return s;
  }
// One symbol, measured over a 1% move in whole ticks (large enough that rounding to cents
// can't matter). False, with the reason, when it has no quotes or can't be calculated.
bool CalibrateSymbol(const string sym,const string acc,FPCalib &c,string &why,string &key,string &csym,bool &inv)
  {
   double ask=SymbolInfoDouble(sym,SYMBOL_ASK);
   if(!(ask>0)){why="no quotes";return false;}
   double tick=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   if(!(tick>0))tick=SymbolInfoDouble(sym,SYMBOL_POINT);
   if(!(tick>0)){why="no tick size";return false;}
   int digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   double close=NormalizeDouble(ask-MathMax(tick,MathRound(ask*0.01/tick)*tick),digits);
   double d=ask-close,profit=0;
   if(!(d>0)){why="price too small to measure";return false;}
   ResetLastError();
   if(!OrderCalcProfit(ORDER_TYPE_BUY,sym,1.0,ask,close,profit)){why="the terminal could not calculate it (error "+IntegerToString(GetLastError())+")";return false;}
   if(!(profit<0)){why="no loss was calculated";return false;}
   c.symbol=sym;c.profit_ccy=SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT);c.account_ccy=acc;
   c.value_account=-profit/d;
   double conv=FPCConv(c.profit_ccy,acc,key,csym,inv);
   c.value_profit=conv>0?c.value_account/conv:0;
   c.contract=SymbolInfoDouble(sym,SYMBOL_TRADE_CONTRACT_SIZE);
   c.tick_size=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   c.tick_value=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   c.time=(long)TimeCurrent();
   return true;
  }
// How far another method is from the measured value: "ok" within 2%, else the factor, e.g. "x10".
string CalOff(const double method,const double measured)
  {
   if(!(method>0) || !(measured>0))return "n/a";
   if(MathAbs(method-measured)<=FPC_TOL*measured)return "ok";
   return "x"+CalNum(method/measured,3);
  }
// A readable copy next to the data file (Fibonacci Pro does not read it).
void WriteReport(const string filename,FPCalib &list[],const int n)
  {
   int f=FileOpen(filename,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f==INVALID_HANDLE)return;
   FileWriteString(f,"symbol;profit currency;per 1.0 move per lot (profit currency);per 1.0 move per lot (account currency);account currency;contract size;tick size;tick value;calibrated\r\n");
   for(int i=0;i<n;i++)
      FileWriteString(f,list[i].symbol+";"+list[i].profit_ccy+";"+CalNum(list[i].value_profit,8)+";"+CalNum(list[i].value_account,8)+";"+list[i].account_ccy+";"
                      +CalNum(list[i].contract,8)+";"+CalNum(list[i].tick_size,10)+";"+CalNum(list[i].tick_value,8)+";"+TimeToString((datetime)list[i].time,TIME_DATE|TIME_MINUTES)+"\r\n");
   FileClose(f);
  }
void OnStart()
  {
   string acc=AccountInfoString(ACCOUNT_CURRENCY);
   if(acc==""){MessageBox("Log in to a trading account first: the calibration needs the account currency.","Fibonacci Pro Calibrate",MB_OK|MB_ICONWARNING);return;}
   FolderCreate("FibonacciPro");
   string file=FPCFile();
   FPCalib list[];
   int n=FPCLoad(file,list);
   if(n<0)n=0;   // missing or unreadable: start a new file
   // Names first: finding a conversion symbol can add it to Market Watch.
   int total=InpAllSymbols?SymbolsTotal(true):1;
   string syms[];
   ArrayResize(syms,total);
   for(int i=0;i<total;i++)syms[i]=InpAllSymbols?SymbolName(i,true):_Symbol;
   string key="",csym="",flagged="",doubted="";
   bool inv=false;
   int done=0,skipped=0,off=0,doubt=0;
   Print("Fibonacci Pro Calibrate: ",total," symbol(s), account currency ",acc,", server ",AccountInfoString(ACCOUNT_SERVER));
   for(int i=0;i<total;i++)
     {
      FPCalib c;
      string why="";
      if(!CalibrateSymbol(syms[i],acc,c,why,key,csym,inv)){skipped++;Print(syms[i],": skipped, ",why);continue;}
      double cv=FPCContractValue(syms[i],acc,key,csym,inv),tv=FPCTickValue(syms[i]);
      string co=CalOff(cv,c.value_account),to=CalOff(tv,c.value_account);
      int k=FPCFind(list,n,syms[i]);
      // Two sources that agree outvote the third: when the contract size and the tick value
      // match each other but not the terminal's calculation, the symbol is left uncalibrated
      // (an older calibration of it is dropped) and Fibonacci Pro uses the two that agree.
      bool agree=cv>0 && tv>0 && MathAbs(cv-tv)<=FPC_TOL*MathMax(cv,tv);
      if(agree && co!="ok" && to!="ok")
        {
         doubt++;doubted+=(StringLen(doubted)>0?", ":"")+syms[i];
         Print(syms[i],": not calibrated, the terminal's calculation (",CalNum(c.value_account,6)," ",acc," per 1.0 move) differs from the contract size and the tick value, which agree (",CalNum(cv,6),")");
         if(k>=0){for(int j=k;j<n-1;j++)list[j]=list[j+1];n--;ArrayResize(list,n);}
         continue;
        }
      if((co!="ok" && co!="n/a") || (to!="ok" && to!="n/a")){off++;flagged+=(StringLen(flagged)>0?", ":"")+syms[i];}
      Print(syms[i],": 1.00 lot = ",CalNum(c.value_account,6)," ",acc," per 1.0 move   contract size: ",co,"   tick value: ",to);
      if(k<0)
        {
         if(n>=FPC_MAX){skipped++;Print(syms[i],": skipped, the file is full");continue;}
         k=n++;ArrayResize(list,n);
        }
      list[k]=c;done++;
     }
   bool saved=(done==0 && doubt==0) || FPCSave(file,list,n);
   if(saved && done>0)WriteReport(file+".csv",list,n);
   string text=saved?"Calibrated "+IntegerToString(done)+" symbol(s) for server "+AccountInfoString(ACCOUNT_SERVER)+".":"Could not write "+file+" (see the Experts log).";
   if(skipped>0)text+="\n"+IntegerToString(skipped)+" skipped (no quotes, or not calculable): see the Experts log.";
   if(off>0)text+="\n\nThe broker's contract size or tick value is off for: "+flagged+".\nFibonacci Pro uses the calibrated values for them.";
   else if(done>0)text+="\n\nContract size and tick value agree with the terminal's calculation on every symbol.";
   if(doubt>0)text+="\n\nNot calibrated: "+doubted+". The terminal's calculation differs from the contract size and the tick value, which agree with each other; Fibonacci Pro uses those.";
   text+="\n\nRun it again if your broker changes contract sizes. It sends no orders.";
   MessageBox(text,"Fibonacci Pro Calibrate",MB_OK|(saved?MB_ICONINFORMATION:MB_ICONWARNING));
  }

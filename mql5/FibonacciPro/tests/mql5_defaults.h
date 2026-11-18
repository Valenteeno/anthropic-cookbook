// Inert default implementations of the MT5 API for the behavioural tests. Tests define
// the object/string/math functions they observe; everything else does nothing here.
#pragma once
long AccountInfoInteger(ENUM_ACCOUNT_INFO_INTEGER){return 0;}
string AccountInfoString(ENUM_ACCOUNT_INFO_STRING){return "";}
bool CCanvas::CreateBitmapLabel(long,int,const string&,int,int,int,int,ENUM_COLOR_FORMAT){return true;}
void CCanvas::Destroy(){}int CCanvas::Width(){return 0;}int CCanvas::Height(){return 0;}void CCanvas::Erase(uint){}void CCanvas::Update(bool){}
void CCanvas::PixelSet(int,int,uint){}void CCanvas::Rectangle(int,int,int,int,uint){}
#ifndef TEST_OWN_CANVAS
void CCanvas::FillRectangle(int,int,int,int,uint){}
#endif
void CCanvas::Line(int,int,int,int,uint){}bool CCanvas::FontSet(const string&,int,uint,uint){return true;}
int CCanvas::TextWidth(const string& t){return (int)t.size()*6;}int CCanvas::TextHeight(const string&){return 14;}void CCanvas::TextOut(int,int,const string&,uint,uint){}
double ChartGetDouble(long,ENUM_CHART_PROPERTY_DOUBLE,int){return 0;}long ChartGetInteger(long,ENUM_CHART_PROPERTY_INTEGER,int){return 0;}
long ChartID(){return 1;}bool ChartIndicatorDelete(long,int,const string&){return true;}bool ChartNavigate(long,ENUM_CHART_POSITION,int){return true;}
void ChartRedraw(long){}bool ChartSetInteger(long,ENUM_CHART_PROPERTY_INTEGER,long){return true;}
#ifndef TEST_OWN_XY
bool ChartTimePriceToXY(long,int,datetime,double,int& x,int& y){x=0;y=0;return false;}
#endif
bool ChartXYToTimePrice(long,int,int,int& s,datetime& t,double& p){s=-1;t=0;p=0;return false;}
uint ColorToARGB(color c,uchar a){return ((uint)a<<24)|(uint)(c&0xFFFFFF);}
int CopyRates(const string&,ENUM_TIMEFRAMES,int,int,MQLArr<MqlRates>&){return 0;}
void EventKillTimer(){}bool EventSetMillisecondTimer(int){return true;}
#ifndef TEST_OWN_FILES
void FileClose(int){}bool FileCopy(const string&,int,const string&,int){return false;}bool FileDelete(const string&,int){return false;}
void FileFindClose(long){}long FileFindFirst(const string&,string&,int){return INVALID_HANDLE;}bool FileFindNext(long,string&){return false;}
void FileFlush(int){}bool FileIsEnding(int){return true;}bool FileIsExist(const string&,int){return false;}
bool FileMove(const string&,int,const string&,int){return false;}int FileOpen(const string&,int,short,uint){return INVALID_HANDLE;}
double FileReadDouble(int){return 0;}int FileReadInteger(int,int){return 0;}long FileReadLong(int){return 0;}string FileReadString(int,int){return "";}
ulong FileSize(int){return 0;}ulong FileTell(int){return 0;}uint FileWriteDouble(int,double){return 0;}uint FileWriteInteger(int,int,int){return 0;}
uint FileWriteLong(int,long){return 0;}uint FileWriteString(int,const string&,int){return 0;}
#endif
bool FolderCreate(const string&,int){return true;}
int GetLastError(){return 0;}void ResetLastError(){}ulong GetMicrosecondCount(){return 0;}
static ulong g_fake_ticks=100000;ulong GetTickCount64(){return g_fake_ticks;}
bool IndicatorSetString(ENUM_CUSTOMIND_PROPERTY_STRING,const string&){return true;}
double MathPow(double a,double b){return std::pow(a,b);}double MathSqrt(double v){return std::sqrt(v);}int MathRand(){return 4242;}void MathSrand(uint){}
#ifndef TEST_OWN_OBJGET
string ObjectGetString(long,const string&,ENUM_OBJECT_PROPERTY_STRING,int){return "";}
#endif
string ObjectName(long,int,int,int){return "";}int ObjectsTotal(long,int,int){return 0;}
long ObjectGetInteger(long,const string&,ENUM_OBJECT_PROPERTY_INTEGER,int){return 0;}
int PeriodSeconds(ENUM_TIMEFRAMES){return 3600;}
string ShortToString(ushort c){return c<128?string(1,(char)c):string("?");}
ushort StringGetCharacter(const string& s,int i){return i>=0 && i<(int)s.size()?(ushort)(unsigned char)s[i]:0;}
int StringSplit(const string& s,ushort sep,MQLArr<string>& r){r.v.clear();string cur;for(char ch:s){if((ushort)(unsigned char)ch==sep){r.v.push_back(cur);cur="";}else cur+=ch;}r.v.push_back(cur);return (int)r.v.size();}
string StringSubstr(const string& s,int st,int len){if(st<0 || st>=(int)s.size())return "";return len<0?s.substr(st):s.substr(st,len);}
double StringToDouble(const string& s){return std::atof(s.c_str());}long StringToInteger(const string& s){return std::atol(s.c_str());}
datetime StringToTime(const string&){return 0;}bool StringToUpper(string& s){for(auto& c:s)c=(char)toupper(c);return true;}
long TerminalInfoInteger(ENUM_TERMINAL_INFO_INTEGER){return 0;}string TimeToString(datetime t,int){return std::to_string(t);}
int iBarShift(const string&,ENUM_TIMEFRAMES,datetime,bool){return -1;}datetime iTime(const string&,ENUM_TIMEFRAMES,int){return 0;}
double iOpen(const string&,ENUM_TIMEFRAMES,int){return 0;}double iHigh(const string&,ENUM_TIMEFRAMES,int){return 0;}
double iLow(const string&,ENUM_TIMEFRAMES,int){return 0;}double iClose(const string&,ENUM_TIMEFRAMES,int){return 0;}
#ifndef TEST_OWN_TIME
datetime TimeTradeServer(){return 0;}datetime TimeGMT(){return 0;}datetime TimeCurrent(){return 0;}
#endif
#ifndef TEST_OWN_RATES
int CopyRates(const string&,ENUM_TIMEFRAMES,datetime,datetime,MQLArr<MqlRates>&){return 0;}
#endif
#ifndef TEST_OWN_ALERTS
bool PlaySound(const string&){return true;}bool SendNotification(const string&){return true;}
bool GlobalVariableTemp(const string&){return true;}bool GlobalVariableSetOnCondition(const string&,double,double){return true;}
#endif
long FileGetInteger(const string&,ENUM_FILE_PROPERTY_INTEGER,bool){return 0;}

//+------------------------------------------------------------------+
//|                                           EconomicIndicators.mq5 |
//|                                         Copyright 2024, Kurokawa |
//|                                   https://twitter.com/ImKurokawa |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Kurokawa"
#property link      "https://twitter.com/ImKurokawa"
#property version   "1.00"
#property indicator_chart_window
#property indicator_color1     clrBlack   //  コンパイル時における警告メッセージ抑止のため
#include <ChartObjects\\ChartObjectsLines.mqh>
#include <Generic\SortedMap.mqh>
#include <Generic\HashMap.mqh>
#include <CheckEnvironment.mqh>
#include <Flag.mqh>

input double ServerTimeOffset = 2.0;            // GMTからの時差（単位は時間）
input double ServerTimeOffsetDuringDST = 2.0;   // サマータイム期間中におけるGMTからの時差（単位は時間、サマータイムが存在しない場合はServerTimeOffsetと同じ値）
input double LocalTimeOffset = 9.0;             // GMTからの時差（単位は時間）
input double LocalTimeOffsetDuringDST = 9.0;    // サマータイム期間中におけるGMTからの時差（（単位は時間、サマータイムが存在しない場合はLocalTimeOffsetと同じ値）

#define EconomicIndicatorObjectName "EconomicIndicator"  //  GUIオブジェクト名のヘッダ部分
#define CSV_FILE_FOLDER   "EconomicIndicators"           //  CSVファイルが格納されているフォルダ。場所はMQL5/Filesフォルダ配下になる
#define ArraySizeEconomicIndicator    1000
#define MaxHorizontalAlignment        300

#define SECONDS_M1         60
#define SECONDS_M2        120
#define SECONDS_M3        180
#define SECONDS_M4        240
#define SECONDS_M5        300
#define SECONDS_M6        360
#define SECONDS_M10       600
#define SECONDS_M12       720
#define SECONDS_M15       900
#define SECONDS_M20      1200
#define SECONDS_M30      1800
#define SECONDS_H1       3600
#define SECONDS_H2       7200
#define SECONDS_H3      10800
#define SECONDS_H4      14400
#define SECONDS_H6      21600
#define SECONDS_H8      28800
#define SECONDS_H12     43200
#define SECONDS_D1      86400
#define SECONDS_W1     604800
#define SECONDS_MN1   2678400

//  オブジェクト描画の状態
enum ObjectStatus
{
   INIT,          //  初期状態（CSVが読まれる必要がある）
   NEED_REDRAW,   //  再描画が必要
   DONE           //  描画完了
};

class EconomicIndicator
{
   public:
      EconomicIndicator(void);
      ~EconomicIndicator(void);   
      void Create(const long chart, const string name, const int subwin);
      void Destroy();
      void SetTime(datetime time);
      void SetCountry(Country country);
      void SetImpact(int impact);
      void SetText(string text);
      void SetAlignment(int alignment);
      datetime GetTime();
      Country GetCountry();
      int GetImpact();
      string GetText();
      int GetAlignment();
      void SetVisible(bool b);
      
   protected:
      datetime time;
      Country country;
      int impact;
      string text;
      int alignment;
      CFlag *flag;
      bool visible;
      CChartObjectVLine *line;   
      static int NumberOfInstances;
};
int EconomicIndicator::NumberOfInstances = 0;

ObjectStatus CurrentObjectStatus;   //  オブジェクト描画の状態
datetime LastCSVLoad = 0;  //  最後にCSVファイルをロードした時刻
EconomicIndicator EconomicIndicators[ArraySizeEconomicIndicator]; //  表示する経済指標を管理するオブジェクト
CHashMap<ENUM_TIMEFRAMES, int> *MapTimeFrame;
CSortedMap<string, EconomicIndicator*> *SortedEconomicIndicators; //  CSVファイルから読み取った経済指標を古い順にソートするために使われる
int SecondsInCandle; //  ローソク足1つあたり何秒か

int OnInit()
{
   if (!CheckEnvironment(ChkExclusiveInChart, NULL, NULL, NULL, NULL))
   {
      ChartIndicatorDelete(0, 0, MQLInfoString(MQL_PROGRAM_NAME));
      return INIT_FAILED;
   }
   
   SortedEconomicIndicators = new CSortedMap<string, EconomicIndicator*>();
   
   MapTimeFrame = new CHashMap<ENUM_TIMEFRAMES, int>();
   MapTimeFrame.Add(PERIOD_M1,  SECONDS_M1);
   MapTimeFrame.Add(PERIOD_M2,  SECONDS_M2);
   MapTimeFrame.Add(PERIOD_M3,  SECONDS_M3);
   MapTimeFrame.Add(PERIOD_M4,  SECONDS_M4);
   MapTimeFrame.Add(PERIOD_M5,  SECONDS_M5);
   MapTimeFrame.Add(PERIOD_M6,  SECONDS_M6);
   MapTimeFrame.Add(PERIOD_M10, SECONDS_M10);
   MapTimeFrame.Add(PERIOD_M12, SECONDS_M12);
   MapTimeFrame.Add(PERIOD_M15, SECONDS_M15);
   MapTimeFrame.Add(PERIOD_M20, SECONDS_M20);
   MapTimeFrame.Add(PERIOD_M30, SECONDS_M30);
   MapTimeFrame.Add(PERIOD_H1,  SECONDS_H1);
   MapTimeFrame.Add(PERIOD_H2,  SECONDS_H2);
   MapTimeFrame.Add(PERIOD_H3,  SECONDS_H3);
   MapTimeFrame.Add(PERIOD_H4,  SECONDS_H4);
   MapTimeFrame.Add(PERIOD_H6,  SECONDS_H6);
   MapTimeFrame.Add(PERIOD_H8,  SECONDS_H8);
   MapTimeFrame.Add(PERIOD_H12, SECONDS_H12);
   MapTimeFrame.Add(PERIOD_D1,  SECONDS_D1);
   MapTimeFrame.Add(PERIOD_W1,  SECONDS_W1);
   MapTimeFrame.Add(PERIOD_MN1, SECONDS_MN1);
   MapTimeFrame.TryGetValue(Period(), SecondsInCandle);
   
   CurrentObjectStatus = INIT;
   
   for (int c = 0; c < ArraySize(EconomicIndicators); c++)
   {
      EconomicIndicators[c].Create(0, StringFormat("EconomicIndicator%04d", c), 0);
      EconomicIndicators[c].SetTime((datetime)0);
   }
   
   LoadCSVFiles();
   EventSetMillisecondTimer(750);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   for (int c = 0; c < ArraySize(EconomicIndicators); c++)
   {
      EconomicIndicators[c].Destroy();
   }
   delete MapTimeFrame;   
   delete SortedEconomicIndicators;
}

void OnTimer()
{
   LoadCSVFiles();
   if (CurrentObjectStatus == NEED_REDRAW)
   {
      DrawLines();
      CurrentObjectStatus = DONE;
   }
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   return rates_total;
}

void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
   if (id == CHARTEVENT_CHART_CHANGE)
   {
      if (CurrentObjectStatus == DONE)
      {
         for (int c = 0; c < ArraySizeEconomicIndicator; c++)
         {
            EconomicIndicators[c].SetVisible(false);
         }
         CurrentObjectStatus = NEED_REDRAW;
      }
   }
}

void EconomicIndicator::EconomicIndicator()
{
   flag = new CFlag();
   line = new CChartObjectVLine();
   NumberOfInstances++;
}

void EconomicIndicator::~EconomicIndicator()
{
   delete flag;
   delete line;
   NumberOfInstances--;
}

void EconomicIndicator::Create(const long chart, const string name, const int subwin)
{
   flag.Create(0, StringFormat("Flag%s", name), 0);
   flag.SetFlag(16, "NO_IMAGE");
   line.Create(0, StringFormat("Line%s", name), 0, (datetime)0);
   
   //  グローバル変数に色が登録されている場合
   if (GlobalVariableCheck(StringFormat("ForegroundColor_%lld", ChartID())))
   {
      line.Color((color)GlobalVariableGet(StringFormat("ForegroundColor_%lld", ChartID())));
   }
   else
   {
      line.Color((color)ChartGetInteger(0, CHART_COLOR_FOREGROUND, 0));
   }
      
   line.Background(true);
   line.Style(STYLE_SOLID);
   this.SetAlignment(0);
   SetVisible(false);
}

void EconomicIndicator::Destroy()
{
   flag.Destroy();
   line.Delete();
}

void EconomicIndicator::SetVisible(bool b)
{
   this.visible = b;   
   int x, y;
   if (b)
   {
      ChartTimePriceToXY(0, 0, this.time, 0, x, y);
      flag.Move(x, 16 * this.GetAlignment());
      line.Time(0, this.time);
   }
   else
   {
      ChartTimePriceToXY(0, 0, 0, 0, x, y);
      flag.Move(x, 0);
      line.Time(0, 0);
   }   
}

void EconomicIndicator::SetTime(datetime t)
{
   this.time = t;
}

void EconomicIndicator::SetCountry(Country c)
{
   this.country = c;
   flag.SetFlag(16, EnumToString(c));
}

void EconomicIndicator::SetImpact(int i)
{
   this.impact = i;
}

void EconomicIndicator::SetText(string t)
{
   this.text = t;
   flag.SetText(t);
}

datetime EconomicIndicator::GetTime()
{
   return this.time;
}

Country EconomicIndicator::GetCountry()
{
   return this.country;
}

int EconomicIndicator::GetImpact()
{
   return this.impact;
}

string EconomicIndicator::GetText()
{
   return this.text;
}

void EconomicIndicator::SetAlignment(int a)
{
   this.alignment = a;
}

int EconomicIndicator::GetAlignment()
{
   return this.alignment;
}

//  チャート画面左端の時間を取得する
datetime ChartMinTime()
{
   datetime min = iTime(Symbol(), PERIOD_CURRENT, (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR));
   return min;
}

//  チャート画面右端の時間を取得する（チャート右端に空白を表示した場合の空白部分まで含まれる）
datetime ChartMaxTime()
{
   int s;
   MapTimeFrame.TryGetValue(Period(), s);
   datetime max = iTime(Symbol(), PERIOD_CURRENT, 0) + 17 * s;
   return max;
}

//  指定された時刻がサマータイム期間中かを返却する
bool CheckDST(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   if (dt.mon <= 2 || dt.mon >= 11) return false;
   if (dt.mon >= 4 && dt.mon <= 9) return true;
      
   datetime c = StringToTime(StringFormat("%04d-%02d-01 02:00:00", dt.year, dt.mon));
   int sun = 0;
   while (true)
   {
      TimeToStruct(c, dt);
      if (dt.day_of_week == 0) sun++;
      if (sun >= 2) break;
      c += 86400;
   }
   
   if (dt.mon == 10 && t < c) return true;
   if (dt.mon == 3  && t >= c) return true;
   return false;
}

void LoadCSVFiles()
{
   if (TimeCurrent() - LastCSVLoad < 1800) return;
   LastCSVLoad = TimeCurrent();
   
   for (int c = 0; c < ArraySize(EconomicIndicators); c++)
   {
      EconomicIndicators[c].SetTime((datetime)0);
   }
   
   //  日足チャート以上の場合は何も表示しない
   if (SecondsInCandle > 86400) return;
   
   int NumberOfLines = 0;
   string filename;
   
   long handle = FileFindFirst(CSV_FILE_FOLDER + "\\*.csv", filename);
   while (handle != INVALID_HANDLE)
   {
      //  ファイルを開く
      int csv_handle = FileOpen(StringFormat(CSV_FILE_FOLDER + "\\%s", filename), FILE_READ | FILE_CSV | FILE_UNICODE, ',', CP_UTF8);  //  ※UTF-8ではなく実際はUTF-16LEとして読み込まれる
      while (!FileIsEnding(csv_handle))
      {
         datetime ttime = (datetime)FileReadString(csv_handle);
                  
         //  クライアント時刻からサーバー時刻への変換
         if (!CheckDST(ttime))
         {
            datetime gmt = (datetime)(ttime - (long)(3600 * LocalTimeOffset));
            ttime = (datetime)(gmt + (long)(3600 * ServerTimeOffset));
         }
         else
         {
            datetime gmt = (datetime)(ttime - (long)(3600 * LocalTimeOffsetDuringDST));
            ttime = (datetime)(gmt + (long)(3600 * ServerTimeOffsetDuringDST));
         }
         
         string country = FileReadString(csv_handle);
         int impact;
         string region;
         string text;
         if (!CFlag::GetRegionMap().TryGetValue(country, region))
         {
            PrintFormat("不明な国名'%s'が指定されています。", country);
            impact = (int)StringToInteger(FileReadString(csv_handle));
            text = FileReadString(csv_handle);
            continue;
         }
         impact = (int)StringToInteger(FileReadString(csv_handle));
         text = FileReadString(csv_handle);
         
         //  国でフィルタ
         string currencies[] = {SymbolInfoString(Symbol(), SYMBOL_CURRENCY_MARGIN), SymbolInfoString(Symbol(), SYMBOL_CURRENCY_PROFIT)}; 
         
         bool found = false;
         for (int c = 0; c < ArraySize(currencies); c++)
         {
            string arCountry;
            CFlag::GetCountryMap().TryGetValue(currencies[c], arCountry);
            arCountry = StringSubstr(arCountry, StringFind(arCountry, ",") + 1);            
            string arRegion;
            CFlag::GetRegionMap().TryGetValue(arCountry, arRegion);
            found |= (region == arRegion);
         }
         
         if (!found) continue;
         
         EconomicIndicators[NumberOfLines].SetTime(ttime);
         EconomicIndicators[NumberOfLines].SetCountry(CFlag::StringToCountry(country));         
         EconomicIndicators[NumberOfLines].SetImpact(impact);
         EconomicIndicators[NumberOfLines].SetText(text);
         EconomicIndicators[NumberOfLines].SetVisible(false);         
         SortedEconomicIndicators.Add(StringFormat("%s%02d", TimeToString(EconomicIndicators[NumberOfLines].GetTime()), NumberOfLines), GetPointer(EconomicIndicators[NumberOfLines]));
         
         NumberOfLines++;
      }
      FileClose(csv_handle);

      if (!FileFindNext(handle, filename)) break;
   }
   FileFindClose(handle);
   CurrentObjectStatus = NEED_REDRAW;
   LastCSVLoad = TimeCurrent();
}

void DrawLines()
{
   datetime HorizontalAlignment[MaxHorizontalAlignment];
   for (int c = 0; c < MaxHorizontalAlignment; c++)
   {
      HorizontalAlignment[c] = (datetime)0;
   }
   
   //  時刻でソートされた状態の経済指標一覧を取得する
   datetime min = ChartMinTime();
   datetime max = ChartMaxTime();
   
   CKeyValuePair<string, EconomicIndicator*> *SortedBuffer[];
   int copyCount = SortedEconomicIndicators.CopyTo(SortedBuffer);
   
   datetime LastDateTime = (datetime)0;
   int AlignmentIndex = 0;
   for (int c = 0; c < SortedEconomicIndicators.Count(); c++)
   {
      if (SortedBuffer[c].Value().GetTime() < min || max < SortedBuffer[c].Value().GetTime())
      {
         //  高速化のためチャートの範囲外は描画しない
         SortedBuffer[c].Value().SetVisible(false);
         continue;
      }
      
      //  オブジェクトの位置を取得する
      int x, y;
      ChartTimePriceToXY(0, 0, SortedBuffer[c].Value().GetTime(), 0, x, y);
      
      if (LastDateTime != SortedBuffer[c].Value().GetTime())
      {
         //  縦方向の位置のリセット
         LastDateTime = SortedBuffer[c].Value().GetTime();
         AlignmentIndex = 0;
         
         //  左上のTicker等のテキストに被らないようにするため
         if (ChartGetInteger(0, CHART_SHOW_OHLC, 0) == true)
         {
            if (x < (4 * (StringLen(Symbol()) + 4 + StringLen(SymbolInfoString(Symbol(), SYMBOL_DESCRIPTION))) + 32 + 4 * 40))
            {
               AlignmentIndex += 1;
            }
         }
         else if (ChartGetInteger(0, CHART_SHOW_TICKER, 0) == true)
         {
            if (x < (4 * (StringLen(Symbol()) + 4 + StringLen(SymbolInfoString(Symbol(), SYMBOL_DESCRIPTION))) + 32))
            {
               AlignmentIndex += 1;
            }
         }
         if (ChartGetInteger(0, CHART_SHOW_ONE_CLICK, 0) == true)
         {
            if (x < 200)
            {
               AlignmentIndex += 4;
            }
         }
      }      
      
      //  左隣のオブジェクトの考慮
      for (; AlignmentIndex < MaxHorizontalAlignment; AlignmentIndex++)
      {
         if (HorizontalAlignment[AlignmentIndex] < SortedBuffer[c].Value().GetTime()) break;
      }
      
      SortedBuffer[c].Value().SetAlignment(AlignmentIndex);
      SortedBuffer[c].Value().SetVisible(true);
      HorizontalAlignment[AlignmentIndex] = SortedBuffer[c].Value().GetTime() + (StringLen(SortedBuffer[c].Value().GetText()) + 2) * SecondsInCandle;
      AlignmentIndex++;
   }
   
   //  ソート結果取得用のバッファを動的に削除する（MQL5の仕様上、動的に削除する必要がある）
   for (int c = 0; c < SortedEconomicIndicators.Count(); c++)
   {
      delete SortedBuffer[c];
   }
}

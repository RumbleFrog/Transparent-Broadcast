#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "Fishy"
#define PLUGIN_VERSION "0.01"

#include <sourcemod>
#include <morecolors>
#include <Transparent_Broadcast>

#pragma newdecls required

//<!-- Main -->
Database hDB;

int Row;
int RowCount;

float Interval;
float CacheLife;

char Cache[][][255];
char Breed[32];
char GameType[32];

Handle Broadcast;
Handle CacheVoid;

Regex CountDown;

//<!-- Convars -->
ConVar cInterval;
ConVar cCacheLife;
ConVar cBreed;

public Plugin myinfo = 
{
	name = "Transparent Broadcast",
	author = PLUGIN_AUTHOR,
	description = "One of the simplest broadcasting plugin",
	version = PLUGIN_VERSION,
	url = "https://keybase.io/rumblefrog"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	hDB = SQL_Connect("transparent_broadcast", true, error, err_max);
	
	if (hDB == INVALID_HANDLE)
		return APLRes_Failure;
	
	char TableCreateSQL[] = "CREATE TABLE IF NOT EXISTS `Transparent_Broadcast` ( `id` INT NOT NULL AUTO_INCREMENT , `message` TEXT NOT NULL , `type` VARCHAR(32) NOT NULL DEFAULT 'chat' , `breed` VARCHAR(256) NOT NULL DEFAULT 'global' , `game` VARCHAR(256) NOT NULL DEFAULT 'all' , `admin_only` TINYINT NOT NULL DEFAULT '0' , `enabled` TINYINT NOT NULL DEFAULT '1' , PRIMARY KEY (`id`), INDEX (`enabled`)) ENGINE = InnoDB CHARSET=utf8mb4 COLLATE utf8mb4_general_ci";
	
	SQL_SetCharset(hDB, "utf8mb4");
			
	hDB.Query(OnTableCreate, TableCreateSQL);
	
	RegPluginLibrary("Transparent_Broadcast");

	CreateNative("TB_AddBroadcast", NativeAddBroadcast);
	
	return APLRes_Success;
}

public void OnTableCreate(Database db, DBResultSet results, const char[] error, any pData)
{
	if (results == null)
		SetFailState("Unable to create table: %s", error);
}

public void OnPluginStart()
{
	RegexError CountDownError;
	char RegexErr[255];
	
	cInterval = CreateConVar("sm_tb_interval", "30.0", "TB Broadcasting Interval", FCVAR_NONE, true, 1.0);
	cCacheLife = CreateConVar("sm_tb_cachelife", "10.0", "TB Broadcasting Interval", FCVAR_NONE, true, 1.0);
	cBreed = CreateConVar("sm_tb_breed", "global", "TB Global ID Identifier", FCVAR_NONE);
	
	AutoExecConfig(true, "Transparent_Broadcast");
	
	Interval = cInterval.FloatValue;
	HookConVarChange(cInterval, OnConvarChange);
	
	CacheLife = cCacheLife.FloatValue;
	HookConVarChange(cCacheLife, OnConvarChange);
	
	cBreed.GetString(Breed, sizeof Breed);
	HookConVarChange(cBreed, OnConvarChange);
	
	GetGameFolderName(GameType, sizeof GameType);
	
	CountDown = new Regex("/({CountDown:([1-9]+)})/", PCRE_CASELESS, RegexErr, sizeof RegexErr, CountDownError);
	
	if (CountDownError != REGEX_ERROR_NONE)
		SetFailState("Failed to compile regex: %s", RegexErr);
	
	LoadToCache();
	
	RegAdminCmd("sm_previewtb", CmdPreview, ADMFLAG_CHAT, "Previews broadcast output");
	RegAdminCmd("tb_admin", CmdVoid, ADMFLAG_GENERIC, "Transparent Broadcast Admin Permission Check");
	
	Broadcast = CreateTimer(Interval, Timer_Broadcast);
	CacheVoid = CreateTimer(CacheLife, Timer_CacheVoid);
}

void LoadToCache()
{
	char Select_Query[1024];
	
	Format(Select_Query, sizeof Select_Query, "SELECT * FROM `Transparent_Broadcast` WHERE `breed` IN('global', '%%%s%%') AND `game` IN('all', '%%%s%%') AND `enabled` = 1", Breed, GameType);
	
	hDB.Query(SQL_OnLoadToCache, Select_Query);
}

public void SQL_OnLoadToCache(Database db, DBResultSet results, const char[] error, any pData)
{
	if (results == null)
		SetFailState("Failed to fetch broadcasts: %s", error); 
		
	RowCount = results.RowCount;
	
	if (RowCount > Row)
		Row = 0;
	
	for (int i = 1; i <= RowCount; i++)
	{
		results.FetchRow();
		
		results.FetchString(1, Cache[i][0], sizeof Cache[][]);
		results.FetchString(2, Cache[i][1], sizeof Cache[][]);
		results.FetchString(5, Cache[i][2], sizeof Cache[][]);
	}
}

public Action Timer_Broadcast(Handle timer)
{
	char Message[255];
	
	Message = Cache[Row][0];
	TB_Type Type = GetBroadcastType(Cache[Row][1]);
	bool AdminOnly = (StringToInt(Cache[Row][2]) == 0) ? false : true;
	
	FormatArguments(Message, sizeof Message);
	
	switch (Type)
	{
		case TB_Chat:
		{
			for (int i = 1; i <= MaxClients; i++)
			{
				if (Client_IsValid(i) && PermCheck(AdminOnly, i))
					CPrintToChat(i, Message);
			}
		}
		case TB_Hint:
		{
			CRemoveTags(Message, sizeof Message);
			
			for (int i = 1; i <= MaxClients; i++)
			{
				if (Client_IsValid(i) && PermCheck(AdminOnly, i))
					PrintHintText(i, Message);
			}
		}
		case TB_Center:
		{
			CRemoveTags(Message, sizeof Message);
			
			for (int i = 1; i <= MaxClients; i++)
			{
				if (Client_IsValid(i) && PermCheck(AdminOnly, i))
					PrintCenterText(i, Message);
			}
		}
		case TB_Menu:
		{
			CRemoveTags(Message, sizeof Message);
			
			Panel hPl = new Panel();
			hPl.DrawText(Message);
			hPl.CurrentKey = 10;
			
			for (int i = 1; i <= MaxClients; i++)
			{
				if (Client_IsValid(i) && PermCheck(AdminOnly, i))
					hPl.Send(i, VoidMenu, 10);
			}
			
			delete hPl;
		}
	}
	
	if (Row >= RowCount)
		Row = 0;
	else
		Row++;
}

public Action Timer_CacheVoid(Handle timer)
{
	LoadToCache();
}

TB_Type GetBroadcastType(const char[] type)
{
	if (StrEqual(type, "chat", false))
		return TB_Chat;
		
	if (StrEqual(type, "hint", false))
		return TB_Hint;
		
	if (StrEqual(type, "center", false))
		return TB_Center;
		
	if (StrEqual(type, "menu", false))
		return TB_Menu;
		
	return TB_Invalid;
}

void FormatArguments(char[] Message, int size)
{
    char Replacement[64];
    RegexError ret;
    
    if (StrContains(Message, "\\n") != -1)
    {
        Format(Replacement, sizeof Replacement, "%c", 13);
        ReplaceString(Message, size, "\\n", Replacement);
    }
    
    int Count = CountDown.Match(Message, ret);
    
    if (Count > 0)
    {
        if (ret == REGEX_ERROR_NONE)
        {
            int CTime = GetTime(), TimeOffset, Days, Hours, Minutes, Seconds;
            char RegexMatch[64], RegexTime[32];
            
            for (int i = 0; i < Count; i++)
            {
                
                CountDown.GetSubString(0, RegexMatch, sizeof RegexMatch);
                CountDown.GetSubString(1, RegexTime, sizeof RegexTime);
                
                TimeOffset = (StringToInt(RegexTime) - CTime);
                
                Days = RoundToFloor((TimeOffset / 86400) * 1.0);
                Hours = RoundToFloor(((TimeOffset % 86400) / 3600) * 1.0);
                Minutes = RoundToFloor(((TimeOffset % 3600) / 60) * 1.0);
                Seconds = (TimeOffset % 60);
                
                Format(Replacement, sizeof Replacement, "%i:%i:%i:%i", Days, Hours, Minutes, Seconds);
                
                ReplaceString(Message, size, RegexMatch, Replacement, false);
            }
        }
    }
    
    if (StrContains(Message, "{currentmap}", false) != -1)
    {
        GetCurrentMap(Replacement, sizeof Replacement);
        ReplaceString(Message, size, "{currentmap}", Replacement, false);
    }
    
    if (StrContains(Message, "{timeleft}", false) != -1)
    {
        int iMins, iSecs, iTimeLeft;
        
        if (GetMapTimeLeft(iTimeLeft) && iTimeLeft > 0)
        {
            iMins = iTimeLeft / 60;
            iSecs = iTimeLeft % 60;
        }
        
        Format(Replacement, sizeof Replacement, "%d:%02d", iMins, iSecs);
        ReplaceString(Message, size, "{timeleft}", Replacement, false);
    }
    
    ConVar hConVar;
    char sConVar[64], sSearch[64], sReplace[64];
    int iEnd = -1, iStart = StrContains(Message, "{"), iStart2;
    
    while (iStart != -1)
    {
        
    	iEnd = StrContains(Message[iStart + 1], "}");
    
    	if (iEnd == -1)
        	break;
    
    	strcopy(sConVar, iEnd + 1, Message[iStart + 1]);
    	Format(sSearch, sizeof(sSearch), "{%s}", sConVar);
    
    	if ((hConVar = FindConVar(sConVar)))
    	{
        	hConVar.GetString(sReplace, sizeof sReplace);
        	ReplaceString(Message, size, sSearch, sReplace, false);
    	}
    
    	iStart2 = StrContains(Message[iStart + 1], "{");
        
        if (iStart2 == -1)
            break;
        
        iStart += iStart2 + 1;
    }
}

public void OnConvarChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == cBreed)
	{
		cBreed.GetString(Breed, sizeof Breed);
		LoadToCache();
	}
	if (convar == cCacheLife)
	{
		CacheLife = cCacheLife.FloatValue;
		KillTimer(CacheVoid);
		CacheVoid = CreateTimer(CacheLife, Timer_CacheVoid);
	}
	if (convar == cInterval)
	{
		Interval = cInterval.FloatValue;
		KillTimer(Broadcast);
		Broadcast = CreateTimer(Interval, Timer_Broadcast);
	}
}

public int NativeAddBroadcast(Handle plugin, int numParams)
{
	//TODO: Insert && LoadToCache()
}

public Action CmdPreview(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "{lightseagreen}[TB] {aqua}sm_previewtb {chartreuse}<type> <message>");
		return Plugin_Handled;
	}
	
	TB_Type Type;
	char TypeBuffer[32], Arg[64], Message[255];
	
	GetCmdArg(1, TypeBuffer, sizeof TypeBuffer);
	
	for (int i = 2; i <= args; i++)
	{
		GetCmdArg(i, Arg, sizeof Arg);
		Format(Message, sizeof Message, "%s %s", Message, Arg);
	}
	
	Type = GetBroadcastType(TypeBuffer);
	
	switch (Type)
	{
		case TB_Chat:
			CPrintToChat(client, Message);
		case TB_Hint:
		{
			CRemoveTags(Message, sizeof Message);
			
			PrintHintText(client, Message);
		}
		case TB_Center:
		{
			CRemoveTags(Message, sizeof Message);
			
			PrintCenterText(client, Message);
		}
		case TB_Menu:
		{
			CRemoveTags(Message, sizeof Message);
			
			Panel hPl = new Panel();
			hPl.DrawText(Message);
			hPl.CurrentKey = 10;
			
			hPl.Send(client, VoidMenu, 10);
			
			delete hPl;
		}
	}
	
	return Plugin_Handled;
}

public Action CmdVoid(int client, int args)
{
	ReplyToCommand(client, "Voided");
	
	return Plugin_Handled;
}

public int VoidMenu(Menu menu, MenuAction action, int param1, int param2) {}

bool PermCheck(bool AdminOnly, int client)
{
	if (AdminOnly == false || CheckCommandAccess(client, "tb_admin", ADMFLAG_GENERIC))
		return true;
		
	return false;
}

stock bool Client_IsValid(int iClient, bool bAlive = false)
{
	if (iClient >= 1 && iClient <= MaxClients && IsClientConnected(iClient) && IsClientInGame(iClient) && !IsFakeClient(iClient) &&
	
	(bAlive == false || IsPlayerAlive(iClient)))
	{
		return true;
	}

	return false;
}
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <multicolors>
#include <store>


//Defines (Could also use an enum, but i'm too lazy ^^)
#define STATUS_NOT_LOADED -1
#define STATUS_LOAD_FAILED -2
#define STATUS_LOAD_SUCCESSFULL -3

#pragma newdecls required

public Plugin myinfo = 
{
	name = "Daily Credits",
	author = "good_live",
	description = "Allow players to get a small amount of credits each day",
	version = "1.0",
	url = "painlessgaming.eu"
};

ArrayList g_aDays;

Database g_hDatabase;

int g_iPlayerStatus[MAXPLAYERS + 1] = { STATUS_NOT_LOADED, ... };
int g_iPlayerTime[MAXPLAYERS + 1] = { -1, ... };
int g_iPlayerDays[MAXPLAYERS + 1] = { -1, ... };

public void OnPluginStart()
{
	//Translation
	LoadTranslations("daily_credits.phrases");
	
	g_aDays = new ArrayList();
	
	ReadConfig();
	
	DB_Connect();
	
	RegConsoleCmd("sm_getcredits", Command_GetCredits, "Get your daily credits");
}

public void OnClientConnected(int client) 
{
	g_iPlayerStatus[client] = STATUS_NOT_LOADED;
	g_iPlayerTime[client] = -1;
	g_iPlayerDays[client] = -1;
}

public void OnClientPostAdminCheck(int client) 
{
	DB_LoadPlayerInfo(client);
}

public Action Command_GetCredits(int client, int args) 
{
	//Check if the player data is already loaded
	if(g_iPlayerStatus[client] != STATUS_LOAD_SUCCESSFULL) 
	{
		CReplyToCommand(0, "%t", "DATA_NOT_LOADED");
		return Plugin_Handled;
	}
	
	//Check if the last time he used this command is more than 24h
	if(GetTime() - g_iPlayerTime[client] < 86400) 
	{
		CReplyToCommand(client, "%t", "ONLY_ONCE_PER_DAY");
		return Plugin_Handled;
	}
	
	//Check if he used this command within the last 48h hours
	if(GetTime() - g_iPlayerTime[client]  < 172800) 
	{
		if(g_iPlayerDays[client] < (g_aDays.Length-1)) 
		{
			g_iPlayerDays[client]++;
		}
	} else {
		g_iPlayerDays[client] = 0;
	}
	
	DB_UpdatePlayerInfo(client, GetTime(), g_iPlayerDays[client]);
	CReplyToCommand(client, "%t", "STREAK", g_iPlayerDays[client], g_aDays.Get(g_iPlayerDays[client]));
	
	Store_SetClientCredits(client, Store_GetClientCredits(client) + g_aDays.Get(g_iPlayerDays[client]));
	
//	This is for non ZephStore
//	char sCommand[32];
//	Format(sCommand, sizeof(sCommand), "sm_credits #%i %i", GetClientUserId(client), g_aDays.Get(g_iPlayerDays[client]));
//	ServerCommand(sCommand);
	
	return Plugin_Handled;
}

void ReadConfig() 
{
	KeyValues kv = new KeyValues("Days");
	
	//Setup Config Path
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/days.cfg");
	
	kv.ImportFromFile(sPath);
	
	if (!kv.GotoFirstSubKey())
		return;
	
	//Read the amount for the current day and save it to the array
	do {
		g_aDays.Push(kv.GetNum("amount", 0));
	} while (kv.GotoNextKey());
	return;
}

void DB_Connect()
{
	if(!SQL_CheckConfig("dailycredits")) 
	{
		SetFailState("Couldn't find the database entry 'dailycredits'!");
	} else {
		Database.Connect(DB_Connect_Callback, "dailycredits");
	}
}

public void DB_Connect_Callback(Database db, const char[] error, any data)
{
	if(db == null)
		SetFailState("Database connection failed!: %s", error);
	
	g_hDatabase = db;
	
	DB_Create_Table();
}

void DB_Create_Table()
{
	char sQuery[512];
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `dailycredits` (`steamid` varchar(21) NOT NULL,`lasttime` int(11) NOT NULL DEFAULT '0',`days` int(11) NOT NULL DEFAULT '0')");
	g_hDatabase.Query(DB_CreateTable_Callback, sQuery);
}

public void DB_CreateTable_Callback(Database db, DBResultSet results, const char[] error, int userid)
{		
	//Check if there was an error
	if(strlen(error) > 0 || results == INVALID_HANDLE) 
	{
		LogError("Failed to create the tables: %s", error);
		return;
	}
	
	//We fire this, when we are sure that the table exists
	OnDatabaseConnected();
}

//This one only gets called internal so it doesn't have to be public
void OnDatabaseConnected()
{
	for (int i = 1; i <= MaxClients; i++) 
	{
		if(!IsClientValid(i))
			continue;
		
		DB_LoadPlayerInfo(i);
	}
}

void DB_LoadPlayerInfo(int client)
{
	if(g_hDatabase == null)
		return;
	
	//Get the players SteamID
	char sSteamID[20];
	if(!GetClientAuthId(client, AuthId_Steam3, sSteamID, sizeof(sSteamID)))
	{
		g_iPlayerStatus[client] = STATUS_LOAD_FAILED;
		LogError("Failed to load the SteamID from %L. Couldn't load the players data.", client);
		return;
	}
	
	//Send Query
	char sQuery[512];
	Format(sQuery, sizeof(sQuery), "SELECT lasttime, days FROM dailycredits WHERE steamid = '%s'", sSteamID);
	g_hDatabase.Query(DB_LoadPlayerID_Callback, sQuery, GetClientUserId(client));
}

public void DB_LoadPlayerID_Callback(Database db, DBResultSet results, const char[] error, int userid)
{
	//Check if the client is still there
	int client = GetClientOfUserId(userid);
	if(!IsClientValid(client))
		return;
		
	//Check if there was an error
	if(strlen(error) > 0 || results == INVALID_HANDLE)
	{
		LogError("Failed to load the id from %L: %s", client, error);
		g_iPlayerStatus[client] = STATUS_LOAD_FAILED;
		return;
	}
	
	//Check if the player is in the database
	results.FetchRow();
	if(!results.RowCount)
	{
		g_iPlayerTime[client] = 0;
		g_iPlayerDays[client] = 0;
		g_iPlayerStatus[client] = STATUS_LOAD_SUCCESSFULL;
	} else {
		g_iPlayerTime[client] = results.FetchInt(0);
		g_iPlayerDays[client] = results.FetchInt(1);
		g_iPlayerStatus[client] = STATUS_LOAD_SUCCESSFULL;	
	}

}

void DB_UpdatePlayerInfo(int client, int time, int days) {
	
	g_iPlayerTime[client] = time;
	g_iPlayerDays[client] = days;
	
	//Get the players SteamID
	char sSteamID[20];
	if(!GetClientAuthId(client, AuthId_Steam3, sSteamID, sizeof(sSteamID)))
	{
		g_iPlayerStatus[client] = STATUS_LOAD_FAILED;
		LogError("Failed to load the SteamID from %L. Couldn't save data.", client);
		return;
	}
	
	char sQuery[512];
	Format(sQuery, sizeof(sQuery), "INSERT INTO dailycredits (steamid, lasttime, days) VALUES('%s', %i, %i) ON DUPLICATE KEY SET lasttime = %i, days = %i;", time, days, sSteamID, time, days);
	g_hDatabase.Query(DB_UpdatePlayerInfo_Callback, sQuery, GetClientUserId(client));
}

public void DB_UpdatePlayerInfo_Callback(Database db, DBResultSet results, const char[] error, int userid)
{
	//Check if the client is still there
	int client = GetClientOfUserId(userid);
	if(!IsClientValid(client))
		return;
		
	//Check if there was an error
	if(strlen(error) > 0 || results == INVALID_HANDLE)
	{
		LogError("Failed to save %L to the database: %s", client, error);
		g_iPlayerStatus[client] = STATUS_LOAD_FAILED;
		return;
	}
}

//*********************** UTIL STUFF *********************************/

bool IsClientValid(int client)
{
	return (1 <= client <= MaxClients && IsClientConnected(client));
}

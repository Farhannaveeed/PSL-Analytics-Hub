import client from './client'

export const getSummary        = ()         => client.get('/summary')
export const getTeams          = ()         => client.get('/teams')
export const getPlayers        = (p={})     => client.get('/players', { params: p })
export const getMatches        = (p={})     => client.get('/matches', { params: p })
export const getInnings        = (matchId)  => client.get(`/innings/${matchId}`)

export const getTopBatsmen     = (season)   => client.get('/stats/top-batsmen',    { params: { season } })
export const getTopBowlers     = (season)   => client.get('/stats/top-bowlers',    { params: { season } })
export const getTeamWinRate    = (season)   => client.get('/stats/team-winrate',   { params: { season } })
export const getVenueAnalysis  = ()         => client.get('/stats/venue-analysis')
export const getPlayerForm     = (player_id)=> client.get('/stats/player-form',    { params: { player_id } })
export const getHeadToHead     = (t1,t2)    => client.get('/stats/head-to-head',   { params: { team1: t1, team2: t2 } })
export const getLeaderboard    = (season)   => client.get('/stats/leaderboard',    { params: { season } })
export const getBoundaries     = (season)   => client.get('/stats/boundaries',     { params: { season } })
export const getPlayerRating   = (pid,s)    => client.get('/stats/player-rating',  { params: { player_id: pid, season: s } })
export const getNRR            = (season)   => client.get('/stats/nrr',            { params: { season } })
export const getCareer         = (pid)      => client.get('/stats/career',         { params: { player_id: pid } })
export const getSeasonTrend    = ()         => client.get('/stats/season-trend')

export const getWindowRanking  = (season)   => client.get('/stats/window/season-ranking',{ params: { season } })
export const getWindowGrowth   = (pid)      => client.get('/stats/window/player-growth',  { params: { player_id: pid } })

export const getIsolationLevel = ()         => client.get('/db/isolation-level')
export const getDynamicQuery   = (p={})     => client.get('/query',                { params: p })

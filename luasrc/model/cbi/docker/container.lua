--[[
LuCI - Lua Configuration Interface
Copyright 2019 lisaac <lisaac.cn@gmail.com>
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
	http://www.apache.org/licenses/LICENSE-2.0
$Id$
]]--

require "luci.util"
local uci = luci.model.uci.cursor()
local docker = require "luci.docker"
local dk = docker.new({debug=true})
container_id = arg[1]
local action = arg[2] or "info"

local response = dk.containers:inspect(container_id)
if response.code == 200 then
  container_info = response.body
end
local networks = dk.networks:list().body

local get_ports = function(d)
  local data
  if d.NetworkSettings and d.NetworkSettings.Ports then
    for inter, out in pairs(d.NetworkSettings.Ports) do
      data = (data and (data .. "<br>") or "") .. out[1]["HostPort"] .. ":" .. inter 
    end
  end
  return data
end

local get_env = function(d)
  local data
  if d.Config and d.Config.Env then
    for _,v in ipairs(d.Config.Env) do
      data = (data and (data .. "<br>") or "") .. v
    end
  end
  return data
end

local get_command = function(d)
  local data
  if d.Config and d.Config.Cmd then
    for _,v in ipairs(d.Config.Cmd) do
      data = (data and (data .. " ") or "") .. v
    end
  end
  return data
end

local get_mounts = function(d)
  local data
  if d.Mounts then
    for _,v in ipairs(d.Mounts) do
      data = (data and (data .. "<br>") or "") .. v["Source"] .. ":" .. v["Destination"] .. (v["Mode"] ~= "" and (":" .. v["Mode"]) or "")
    end
  end
  return data
end


local get_links = function(d)
  local data
  if d.HostConfig and d.HostConfig.Links then
    for _,v in ipairs(d.HostConfig.Links) do
      data = (data and (data .. "<br>") or "") .. v
    end
  end
  return data
end

local get_networks = function(d)
  local data={}
  if d.NetworkSettings and d.NetworkSettings.Networks and type(d.NetworkSettings.Networks) == "table" then
    for k,v in pairs(d.NetworkSettings.Networks) do
      data[k] = v.IPAddress or ""
    end
  end
  return data
end


m=SimpleForm("docker", translate("Docker Container"), container_info.Name:sub(2))
m:append(Template("docker/container"))

if action == "info" then 
  table_info = {
    ["01name"] = {_key = translate("Name"),  _value = container_info.Name:sub(2)  or "-", _button=translate("Update")},
    ["02id"] = {_key = translate("ID"),  _value = container_info.Id  or "-"},
    ["03image"] = {_key = translate("Image"),  _value = container_info.Config.Image .. "<br>" .. container_info.Image},
    ["04status"] = {_key = translate("Status"),  _value = container_info.State and container_info.State.Status  or "-"},
    ["05created"] = {_key = translate("Created"),  _value = container_info.Created  or "-"},
  }
  table_info["06start"] = container_info.State.Status == "running" and {_key = translate("Start Time"),  _value = container_info.State and container_info.State.StartedAt or "-"} or {_key = translate("Finish Time"),  _value = container_info.State and container_info.State.FinishedAt or "-"}
  table_info["07healthy"] = {_key = translate("Healthy"),  _value = container_info.State and container_info.State.Health and container_info.State.Health.Status or "-"}
  table_info["08restart"] = {_key = translate("Restart Policy"),  _value = container_info.HostConfig and container_info.HostConfig.RestartPolicy and container_info.HostConfig.RestartPolicy.Name or "-", _button=translate("Update")}
  table_info["09mount"] = {_key = translate("Mount/Volume"),  _value = get_mounts(container_info)  or "-"}
  table_info["10cmd"] = {_key = translate("Command"),  _value = get_command(container_info) or "-"}
  table_info["11env"] = {_key = translate("Env"),  _value = get_env(container_info)  or "-"}
  table_info["12ports"] = {_key = translate("Ports"),  _value = get_ports(container_info) or "-"}
  table_info["13links"] = {_key = translate("Links"),  _value = get_links(container_info)  or "-"}
  info_networks = get_networks(container_info)
  list_networks = {}
  for _, v in ipairs (networks) do
    if v.Name then
      local parent = v.Options and v.Options.parent or nil
      local ip = v.IPAM and v.IPAM.Config and v.IPAM.Config[1] and v.IPAM.Config[1].Subnet or nil
      ipv6 =  v.IPAM and v.IPAM.Config and v.IPAM.Config[2] and v.IPAM.Config[2].Subnet or nil
      local network_name = v.Name .. " | " .. v.Driver  .. (parent and (" | " .. parent) or "") .. (ip and (" | " .. ip) or "").. (ipv6 and (" | " .. ipv6) or "")
      list_networks[v.Name] = network_name
    end
  end


  if type(info_networks)== "table" then
    for k,v in pairs(info_networks) do
      table_info["14network"..k] = {
        _key = translate("Network"),  _value = k.. (v~="" and (" | ".. v) or ""), _button=translate("Disconnect")
      }
      list_networks[k]=nil
    end
  end

  table_info["15connect"] = {_key = translate("Connect Network"),  _value = list_networks ,_opts = "", _button=translate("Connect")}


  d_info = m:section(Table,table_info)
  d_info.nodescr=true
  d_info.formvalue=function(self, section)
    return table_info
  end
  dv_key = d_info:option(DummyValue, "_key")
  dv_value = d_info:option(ListValue, "_value")
  dv_value.render = function(self, section, scope)
    if table_info[section]._key == translate("Name") then
      self:reset_values()
      self.template = "cbi/value"
      self.size = 30
      self.keylist = {}
      self.vallist = {}
      self.default=table_info[section]._value
      Value.render(self, section, scope)
    elseif table_info[section]._key == translate("Restart Policy") then
      self.template = "cbi/lvalue"
      self:reset_values()
      self.size = nil
      self:value("no", "No")
      self:value("unless-stopped", "Unless stopped")
      self:value("always", "Always")
      self:value("on-failure", "On failure")
      self.default=table_info[section]._value
      ListValue.render(self, section, scope)
    elseif table_info[section]._key == translate("Connect Network") then
      self.template = "cbi/lvalue"
      self:reset_values()
      self.size = nil
      for k,v in pairs(list_networks) do
        self:value(k,v)
      end
      self.default=table_info[section]._value
      ListValue.render(self, section, scope)
    else
      self:reset_values()
      self.rawhtml=true
      self.template = "cbi/dvalue"
      self.default=table_info[section]._value
      DummyValue.render(self, section, scope)
    end
  end
  dv_value.forcewrite = true -- for write function using simpleform 
  dv_value.write = function(self, section, value)
    table_info[section]._value=value
  end
  dv_value.validate = function(self, value)
    return value
  end
  dv_opts = d_info:option(Value, "_opts")
  dv_opts.forcewrite = true -- for write function using simpleform 
  dv_opts.write = function(self, section, value)

    table_info[section]._opts=value
  end
  dv_opts.validate = function(self, value)
    return value
  end
  dv_opts.render = function(self, section, scope)
    if table_info[section]._key==translate("Connect Network") then
      self.template="cbi/value"
      self.keylist = {}
      self.vallist = {}
      self.placeholder = "10.1.1.254"
      self.datatype = "ip4addr"
      self.default=table_info[section]._opts
      Value.render(self, section, scope)
    else
      self.rawhtml=true
      self.template = "cbi/dvalue"
      self.default=table_info[section]._opts
      DummyValue.render(self, section, scope)
    end
  end
  btn_update = d_info:option(Button, "_button")
  btn_update.forcewrite = true
  btn_update.render = function(self, section, scope)
    if table_info[section]._button and table_info[section]._value ~= nil then
      btn_update.inputtitle=table_info[section]._button
      self.template = "cbi/button"
      Button.render(self, section, scope)
    else 
      self.template = "cbi/dummyvalue"
      self.default=""
      DummyValue.render(self, section, scope)
    end
  end
  btn_update.write = function(self, section, value)
    -- luci.util.perror(section)
    local res
    if section == "01name" then
      local new_name = table_info[section]._value
      res = dk.containers:rename(container_id,{name=new_name})
    elseif section == "08restart" then
      local new_restart = table_info[section]._value
      res = dk.containers:update(container_id, nil, {RestartPolicy = {Name = new_restart}})
    elseif table_info[section]._key == translate("Network") then
      local _,_,leave_network = table_info[section]._value:find("(.-) | .+")
      leave_network = leave_network or table_info[section]._value
      res = dk.networks:disconnect(leave_network, nil, {Container = container_id})
    elseif section == "15connect" then
      local connect_network = table_info[section]._value
      local network_opiton
      if connect_network ~= "none" and connect_network ~= "bridge" and connect_network ~= "host" then
        -- luci.util.perror(table_info[section]._opts)
        network_opiton = table_info[section]._opts ~= "" and {
            IPAMConfig={
              IPv4Address=table_info[section]._opts
            }
        } or nil
      end
      res = dk.networks:connect(connect_network, nil, {Container = container_id, EndpointConfig= network_opiton})
    end
    if res and res.code < 300 then
      luci.http.redirect(luci.dispatcher.build_url("admin/docker/container/"..container_id.."/info"))
    else
      m.message=res and (res.code..": "..res.body.message) or "unknow err"
    end
  end
  
-- info end
elseif action == "edit" then
  editsection= m:section(SimpleSection)
  d = editsection:option( Value, "cpus", translate("CPUs"), translate("Number of CPUs. Number is a fractional number. 0.000 means no limit."))
  d.placeholder = "1.5"
  d.rmempty = true
  d.datatype="ufloat"
  d.default = container_info.HostConfig.NanoCpus / (10^9)

  d = editsection:option(Value, "cpushares", translate("CPU Shares Weight"), translate("CPU shares (relative weight, if 0 is set, the system will ignore the value and use the default of 1024."))
  d.placeholder = "1024"
  d.rmempty = true
  d.datatype="uinteger"
  d.default = container_info.HostConfig.CpuShares

  d = editsection:option(Value, "memory", translate("Memory"), translate("Memory limit (format: <number>[<unit>]). Number is a positive integer. Unit can be one of b, k, m, or g. Minimum is 4M."))
  d.placeholder = "128m"
  d.rmempty = true
  d.default = container_info.HostConfig.Memory

  d = editsection:option(Value, "blkioweight", translate("Block IO Weight"), translate("Block IO weight (relative weight) accepts a weight value between 10 and 1000."))
  d.placeholder = "500"
  d.rmempty = true
  d.datatype="uinteger"
  d.default = container_info.HostConfig.BlkioWeight

elseif action == "logs" then
  logsection= m:section(SimpleSection)
  local logs = ""
  local query ={
    stdout = 1,
    stderr = 1,
    tail = 1000
  }
	local logs = dk.containers:logs(container_id, query)
  if logs.code == 200 then
    logsection.syslog=logs.body
  else
    logsection.syslog="Get Logs ERROR\n"..logs.code..": "..logs.body
  end
  logsection.title=translate("Container Logs")
  logsection.template="docker/logs"
  m.submit = false
	m.reset  = false
elseif action == "stats" then
  local response = dk.containers:top(container_id, {ps_args="-aux"})
  if response.code == 200 then
    container_top=response.body
    table_top = container_top.Processes
    stat_section = m:section(SimpleSection)
    stat_section.container_id = container_id
    stat_section.template="docker/stats"
    top_section= m:section(Table, table_top, translate("TOP"))
    top_section:option(DummyValue, 1, translate(container_top.Titles[1]))
    top_section:option(DummyValue, 2, translate(container_top.Titles[2]))
    top_section:option(DummyValue, 3, translate(container_top.Titles[3]))
    top_section:option(DummyValue, 4, translate(container_top.Titles[4]))
    top_section:option(DummyValue, 5, translate(container_top.Titles[5]))
    top_section:option(DummyValue, 6, translate(container_top.Titles[6]))
    top_section:option(DummyValue, 7, translate(container_top.Titles[7]))
    top_section:option(DummyValue, 8, translate(container_top.Titles[8]))
    top_section:option(DummyValue, 9, translate(container_top.Titles[9]))
    top_section:option(DummyValue, 10, translate(container_top.Titles[10]))
    top_section:option(DummyValue, 11, translate(container_top.Titles[11]))
    -- top_section.nodescr=true
  end
  m.submit = false
	m.reset  = false
end

m.handle = function(self, state, data)
  if state == FORM_VALID then
    local memory = data.memory
    if memory ~= 0 then
      _,_,n,unit = memory:find("([%d%.]+)([%l%u]+)")
      if n then
        unit = unit and unit:sub(1,1):upper() or "B"
        if  unit == "M" then
          memory = tonumber(n) * 1024 * 1024
        elseif unit == "G" then
          memory = tonumber(n) * 1024 * 1024 * 1024
        elseif unit == "K" then
          memory = tonumber(n) * 1024
        else
          memory = tonumber(n)
        end
      end
    end
    request_body = {
      BlkioWeight = tonumber(data.blkioweight),
      NanoCPUs = tonumber(data.cpus)*10^9,
      Memory = tonumber(memory),
      CpuShares = tonumber(data.cpushares)
      }
    local res = dk.containers:update(container_id, nil, request_body)
    if res and res.code < 300 then
      luci.http.redirect(luci.dispatcher.build_url("admin/docker/container/"..container_id.."/edit"))
    else
      m.message=res and (res.code..": "..res.body.message) or "unknow err"
    end
  end
end
return m
-- Access to the RemoteEvents declared in default.project.json (ReplicatedStorage.RemoteEvents).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("RemoteEvents")

local Remotes = {}

function Remotes.get(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes

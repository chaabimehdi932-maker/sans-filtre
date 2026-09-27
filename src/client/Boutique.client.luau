-- Interface de la boutique : un bouton en bas à gauche qui ouvre la liste des articles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local acheter = ReplicatedStorage:WaitForChild("Acheter") :: RemoteFunction

local player = Players.LocalPlayer

local OR = Color3.fromRGB(255, 200, 40)
local SOMBRE = Color3.fromRGB(25, 25, 30)
local VERT = Color3.fromRGB(80, 200, 110)
local ROUGE = Color3.fromRGB(230, 80, 80)
local GRIS = Color3.fromRGB(90, 90, 95)

local function arrondir(objet: GuiObject, rayon: number)
	local coin = Instance.new("UICorner")
	coin.CornerRadius = UDim.new(0, rayon)
	coin.Parent = objet
end

local gui = Instance.new("ScreenGui")
gui.Name = "Boutique"
gui.ResetOnSpawn = false

local ouvrir = Instance.new("TextButton")
ouvrir.Size = UDim2.fromOffset(140, 50)
ouvrir.Position = UDim2.new(0, 16, 1, -70)
ouvrir.BackgroundColor3 = OR
ouvrir.TextColor3 = SOMBRE
ouvrir.Font = Enum.Font.GothamBold
ouvrir.TextSize = 22
ouvrir.Text = "Boutique"
ouvrir.Parent = gui
arrondir(ouvrir, 10)

local fenetre = Instance.new("Frame")
fenetre.Size = UDim2.fromOffset(340, 90 + #Config.BOUTIQUE * 60)
fenetre.Position = UDim2.fromScale(0.5, 0.5)
fenetre.AnchorPoint = Vector2.new(0.5, 0.5)
fenetre.BackgroundColor3 = SOMBRE
fenetre.BackgroundTransparency = 0.1
fenetre.Visible = false
fenetre.Parent = gui
arrondir(fenetre, 14)

local titre = Instance.new("TextLabel")
titre.Size = UDim2.new(1, -60, 0, 40)
titre.Position = UDim2.fromOffset(16, 8)
titre.BackgroundTransparency = 1
titre.TextColor3 = OR
titre.Font = Enum.Font.GothamBold
titre.TextSize = 26
titre.TextXAlignment = Enum.TextXAlignment.Left
titre.Text = "Boutique"
titre.Parent = fenetre

local fermer = Instance.new("TextButton")
fermer.Size = UDim2.fromOffset(36, 36)
fermer.Position = UDim2.new(1, -46, 0, 10)
fermer.BackgroundColor3 = GRIS
fermer.TextColor3 = Color3.new(1, 1, 1)
fermer.Font = Enum.Font.GothamBold
fermer.TextSize = 20
fermer.Text = "X"
fermer.Parent = fenetre
arrondir(fermer, 8)

local liste = Instance.new("Frame")
liste.Size = UDim2.new(1, -32, 1, -90)
liste.Position = UDim2.fromOffset(16, 52)
liste.BackgroundTransparency = 1
liste.Parent = fenetre

local disposition = Instance.new("UIListLayout")
disposition.Padding = UDim.new(0, 8)
disposition.SortOrder = Enum.SortOrder.LayoutOrder
disposition.Parent = liste

local info = Instance.new("TextLabel")
info.Size = UDim2.new(1, -32, 0, 24)
info.Position = UDim2.new(0, 16, 1, -32)
info.BackgroundTransparency = 1
info.Font = Enum.Font.Gotham
info.TextSize = 18
info.Text = ""
info.Parent = fenetre

for ordre, article in Config.BOUTIQUE do
	local attribut = "Achat_" .. article.id

	local ligne = Instance.new("Frame")
	ligne.Size = UDim2.new(1, 0, 0, 52)
	ligne.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
	ligne.LayoutOrder = ordre
	ligne.Parent = liste
	arrondir(ligne, 10)

	local nom = Instance.new("TextLabel")
	nom.Size = UDim2.new(1, -140, 1, 0)
	nom.Position = UDim2.fromOffset(12, 0)
	nom.BackgroundTransparency = 1
	nom.TextColor3 = Color3.new(1, 1, 1)
	nom.Font = Enum.Font.GothamMedium
	nom.TextSize = 18
	nom.TextXAlignment = Enum.TextXAlignment.Left
	nom.Text = article.nom
	nom.Parent = ligne

	local bouton = Instance.new("TextButton")
	bouton.Size = UDim2.fromOffset(116, 36)
	bouton.Position = UDim2.new(1, -124, 0.5, -18)
	bouton.TextColor3 = SOMBRE
	bouton.Font = Enum.Font.GothamBold
	bouton.TextSize = 16
	bouton.Parent = ligne
	arrondir(bouton, 8)

	local function mettreAJour()
		if player:GetAttribute(attribut) then
			bouton.Text = "Acheté"
			bouton.BackgroundColor3 = GRIS
			bouton.AutoButtonColor = false
		else
			bouton.Text = article.prix .. " pièces"
			bouton.BackgroundColor3 = OR
			bouton.AutoButtonColor = true
		end
	end
	player:GetAttributeChangedSignal(attribut):Connect(mettreAJour)
	mettreAJour()

	bouton.Activated:Connect(function()
		if player:GetAttribute(attribut) then
			return
		end
		local ok, message = acheter:InvokeServer(article.id)
		info.Text = message
		info.TextColor3 = if ok then VERT else ROUGE
	end)
end

ouvrir.Activated:Connect(function()
	fenetre.Visible = not fenetre.Visible
	info.Text = ""
end)
fermer.Activated:Connect(function()
	fenetre.Visible = false
end)

gui.Parent = player:WaitForChild("PlayerGui")

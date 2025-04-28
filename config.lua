Config = {}

Config.Lang = 'en'
Config.ApiaryItem = 'beehive' -- Item to trigger barrel placement
Config.MaxApiaries = 5 -- Maximum number of barrels
Config.ApiaryRadius = 1 -- Radius for random spawn around player
Config.InteractDistance = 2.0 -- Distance for ox_target interaction
Config.BeeDistance = 10.0 -- Distance for bee particle effects

-- Materials needed for honey production
Config.Materials = {
    { item = 'honeyframe', amount = 2, label = 'honeyframe' }
}

-- Production timer (in minutes)
Config.ProductionTime = 30 -- Time until honey is ready


Config.Apiaries = {
    { name = 'Barrel', hash = 570671881, model = 'p_barrel05b' }
}


Config.BeeParticle = {
    group = 'core',
    name = 'ent_amb_insect_bee_swarm'
}


Config.Anim = {
    dict = 'amb_work@world_human_box_pickup@1@male_a@stand_exit_withprop',
    name = 'exit_front',
    duration = 2300,
    placingDict = 'amb_work@world_human_box_pickup@1@male_a@stand_exit_withprop',
    placingName = 'exit_front',
    placingDuration = 4000
}


Config.Rewards = {
    { item = 'honey', min = 1, max = 3, chance = 100 },
    
}


Config.Text = {
    collect = 'Collect honey',
    add_materials = 'Add honeyframe',
    check_status = 'Check status',
    collected = 'Honey collected',
    empty = 'Beehive empty',
    beekeeper = 'Beekeeper',
    placed = 'You placed a barrel apiary!',
    no_materials = 'You need more honeyframes!',
    materials_added = 'Materials added to makeshift beehive',
    not_ready = 'Honey is not ready yet',
    invalid_location = 'Cannot place beehive here',
    time_remaining = 'Time remaining: %s minutes'
}
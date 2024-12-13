//
//  ZPGameScene.swift
//  Zombocalypse
//
//  
//

import SpriteKit
import GameplayKit
import CoreGraphics

extension CGPoint {
    func distance(to otherPoint: CGPoint) -> CGFloat {
        let dx = otherPoint.x - self.x
        let dy = otherPoint.y - self.y
        return sqrt(dx * dx + dy * dy)
    }
}
extension CGVector {
    var normalized: CGVector {
        let length = sqrt(dx * dx + dy * dy)
        return length > 0 ? CGVector(dx: dx / length, dy: dy / length) : .zero
    }
}

struct Wave {
    let waveNumber: Int
    let totalEnemies: Int
    let regularEnemies: Int
    let chargerEnemies: Int
    let exploderEnemies: Int
    let isHorde: Bool
    let isBoss: Bool
    let spawnInterval: TimeInterval
    let requiresFullClearance: Bool
    
    // Track spawned enemies
    var spawnedRegular: Int = 0
    var spawnedCharger: Int = 0
    var spawnedExploder: Int = 0
    
    // Determine if all enemies have been spawned
    var allEnemiesSpawned: Bool {
        return (spawnedRegular >= regularEnemies) &&
               (spawnedCharger >= chargerEnemies) &&
               (spawnedExploder >= exploderEnemies)
    }
    
    // Initialize without default values for spawned counts
    init(waveNumber: Int, totalEnemies: Int, regularEnemies: Int, chargerEnemies: Int, exploderEnemies: Int, isHorde: Bool, isBoss: Bool, spawnInterval: TimeInterval, requiresFullClearance: Bool) {
        self.waveNumber = waveNumber
        self.totalEnemies = totalEnemies
        self.regularEnemies = regularEnemies
        self.chargerEnemies = chargerEnemies
        self.exploderEnemies = exploderEnemies
        self.isHorde = isHorde
        self.isBoss = isBoss
        self.spawnInterval = spawnInterval
        self.requiresFullClearance = requiresFullClearance
    }
}


class ZPGameScene: SKScene, PlayerStateDelegate {
    //Player Properties
    var playerState = PlayerState()
    var skillManager: SkillManager!
    var enemyManager: EnemyManager!
    var mapManager: MapManager!
    
    //Skills related settings
    var bladesContainer: SKNode?
    var barrierContainer: SKNode?
    var shieldContainer: SKNode?
    var spectralShield: SKShapeNode?

    var lastGrenadeTime: TimeInterval = 0
    var grenadeShootInterval: TimeInterval = 5.0
    
    //Inf background settings
    let sectionWidth: CGFloat = 3340 // Example width of each section (Adjust based on image) 1024
    let sectionHeight: CGFloat = 3510 // Example height of each section (Adjust as needed) 768
    let numSections: Int = 5         // Number of sections (Higher = longer before repeated gen., Lower = shorter before repeated gen.)
    
    var currentGameTime: TimeInterval = 0
    weak var context: ZPGameContext?
    var joystick: ZPJoystick!
    var shootJoystick: ZPJoystick!
    var player: SKSpriteNode!
    private var isPlayerFlashing: Bool = false
    var crossbowNode: SKSpriteNode!
    var playerHealthBar: HealthBarNode!
    var playerShootingProgressBar: HealthBarNode!
    var shootingProgress: CGFloat = 1.0 { // 0.0 (not ready) to 1.0 (ready)
        didSet {
            playerShootingProgressBar.setProgress(shootingProgress)
        }
    }
    
    var damagingEnemies: Set<ZPZombie> = [] // Set to keep track of enemies currently damaging the player
    let damageInterval: TimeInterval = 1.0 // Enemy damage interval
    var lastDamageTime: TimeInterval = 0.0
    let zombieCount = 3
    var zombieSpeed: CGFloat = 0.4
    let zombieBufferDistance: CGFloat = 10 // Adjust this value to experiment with zombie spacing w one another
    var playerLivesLabel: SKLabelNode!
    var playerLives: Double = 3.0 {
        didSet {
            playerLivesLabel.text = "Lives: \(playerLives)"
            playerHealthBar.setHealth(playerLives)
        }
    }
    var gameOver: Bool = false
    var isGamePaused: Bool = false
    private var waveTransitionTimer: PausableTimer?
    private var remainingGracePeriod: TimeInterval = 0.0
    private var isGracePeriodActive: Bool = false
    
    //Revamp wave settings
    var enemiesToDefeat = 3
    var miniWaveInterval: TimeInterval = 3.0
    var maxEnemiesOnScreen: Int = 3
    var progressLabel: SKLabelNode!
    var spawningInProgress: Bool = false
    var isTransitioningWave: Bool = false
    
    var maxRegularZombies: Int = 3
    var maxChargerZombies: Int = 0
    var maxExploderZombies: Int = 0
    var isBossStage: Bool = false
    
    //New wave settings
    var waveCycle: [Wave] = []
    var currentWaveIndex: Int = 0
    var gracePeriod: TimeInterval = 7.0
    var pendingEnemies: Int = 0
    var enemiesToSpawn: Int = 0
    var waveProgressionWorkItem: DispatchWorkItem?
    
    // Zombie Wave Settings
    private var zombieHealth: Double = 3.0
    private var wizardHealth: Double = 15.0
    private var wizardBoss: ZPWizard?
    var activeBeamContacts: Set<SKPhysicsBody> = []
    var beamDamageTimer: Timer?
    
    var arenaBounds: CGRect?
    private let waveMessageLabel = SKLabelNode(fontNamed: "Arial")
    
    //Enemy variation message settings
    private let newEnemyMessages: [Int: String] = [
        4: "New Enemy: Charger!",
        5: "New Enemy: Exploder!",
        7: "New Boss: Wizard!",
    ]
    private let newEnemyBannerMapping: [Int: String] = [
        4: "sk_charger_banner",
        5: "sk_exploder_banner"
    ]
    private var displayedEnemyMessages: Set<Int> = []
    
    // Auto-attack variables
    private var lastShootTime: TimeInterval = 0
    
    var scoreNode: SKSpriteNode!
    var scoreLabel: SKLabelNode!
    var waveNode: SKSpriteNode!
    var waveLabel: SKLabelNode!
    var topOverlayNode: SKShapeNode!
    var score: Int = 0 {
        didSet {
            scoreLabel.text = "\(score)"
        }
    }
    private var waveCounter: Int = 0 {
        didSet {
            // Just show the wave number
            waveLabel.text = "\(waveCounter)"
        }
    }
    
    // Track time since the last frame for smoother movement
    private var lastUpdateTime: TimeInterval = 0
    private let centerPosition: CGPoint
    private var activeTouches: [UITouch: ZPJoystick] = [:]
        
    //Upgrades Settings
    var upgradeStatsLabel: SKLabelNode!
    
    var upgradeShopManager: UpgradeShopManager!
    var overlayManager: OverlayManager!
    private var upgradeOverlay: UpgradeShopOverlayNode?
    
    var xpBarNode: XPBarNode!
    var xpNodes: [XPNode] = []
    var xpNodesToRemove: [XPNode] = []
    var xpSpawnTimer: Timer?
    let xpSpawnInterval: TimeInterval = 1.0

    init(context: ZPGameContext, size: CGSize) {
        self.context = context
        self.centerPosition = CGPoint(x: size.width / 2, y: size.height / 2 - 400) //Added '- 400' to make player spawn down towards center of image
        super.init(size: size)
        self.scaleMode = .resizeFill
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMove(to view: SKView) {
        
        playerState.delegate = self
        skillManager = SkillManager(player: playerState)
        upgradeShopManager = UpgradeShopManager(scene: self, skillManager: skillManager)
        overlayManager = OverlayManager(scene: self)
        enemyManager = EnemyManager(scene: self)
        mapManager = MapManager(sectionWidth: (size.height * 2.0) * 0.95331, sectionHeight: size.height * 2.0, numSections: 5, scene: self)
        mapManager.setupBackground(in: self, withTexture: "sk_map")
        
        self.physicsWorld.contactDelegate = self
                
        self.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        self.view?.isMultipleTouchEnabled = true
        let cameraNode = SKCameraNode()
        self.camera = cameraNode
        addChild(cameraNode)
        
        //Initialize HealthBar for player
        let healthBarSize = CGSize(width: 80, height: 7)
        playerHealthBar = HealthBarNode(
            size: healthBarSize,
            maxHealth: playerState.baseMaxHealth,
            foregroundColor: UIColor(hex: "#00C300") ?? .green,
            backgroundColor: UIColor(hex: "#004500") ?? .black
        )
        playerHealthBar.position = CGPoint(x: 0, y: 50)
        playerHealthBar.zPosition = 5
        //Initialize shooting progress bar
        let progressBarSize = CGSize(width: healthBarSize.width * 0.9, height: healthBarSize.height / 2)
        playerShootingProgressBar = HealthBarNode(
            size: progressBarSize,
            maxHealth: 1.0, //Represents progress from 0.0 to 1.0
            foregroundColor: UIColor(hex: "#01403D") ?? .darkGray, //This changes the color that is behind the shootprogressbar
            backgroundColor: .black,
            showProgressBar: true,
            progressColor: UIColor(hex: "#00DCD1") ?? .blue
        )
        playerShootingProgressBar.position = CGPoint(x: 0, y: -healthBarSize.height) // Positioned below the health bar
        playerHealthBar.addChild(playerShootingProgressBar)
        
        setUpGame()
        //Wave message label (center of screen every round)
        waveMessageLabel.fontSize = 40
        waveMessageLabel.fontColor = .red
        waveMessageLabel.position = CGPoint(x: size.width / 2, y: size.height - 180)
        waveMessageLabel.zPosition = 5
        waveMessageLabel.isHidden = true
//        cameraNode.addChild(waveMessageLabel)
        
        //Add camera-related HUD elements
//        cameraNode.addChild(playerLivesLabel)
        cameraNode.addChild(playerHealthBar)
        cameraNode.addChild(scoreNode)
        cameraNode.addChild(waveNode)
        cameraNode.addChild(topOverlayNode)
//        cameraNode.addChild(progressLabel)
        cameraNode.addChild(joystick)
        cameraNode.addChild(shootJoystick)
        
        beamDamageTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.applyBeamDamage()
        }
        
//        let spinningBladesSkill = skillManager.createRegularSkillInstance(for: .spinningBlades)
//        skillManager.acquireOrUpgradeRegularSkill(spinningBladesSkill!)
        
//        let protectiveBarrierSkill = skillManager.createRegularSkillInstance(for: .protectiveBarrier)
//        skillManager.acquireOrUpgradeRegularSkill(protectiveBarrierSkill!)
        
//        let freezeSkill = skillManager.createRegularSkillInstance(for: .freeze)
//        skillManager.acquireOrUpgradeRegularSkill(freezeSkill!)

//        skillManager.acquireSpecialSkill(.helpingHand)
//        skillManager.acquireSpecialSkill(.spectralShield)
//        skillManager.acquireSpecialSkill(.reinforcedArrow)
 //       skillManager.acquireSpecialSkill(.mightyKnockback)
    }
    
    deinit {
        beamDamageTimer?.invalidate()
    }
    
    func setUpGame() {
        backgroundColor = .white
        gameOver = false
        playerState.resetToBaseStats()
        
        // Sets up player at fixed start position
        if player == nil {
            player = SKSpriteNode(imageNamed: "sk_player_right")
            player.setScale(0.5)
            player.position = centerPosition
            player.color = .white // Default color
            player.colorBlendFactor = 0.0
            
            // MARK: Physics
            player.physicsBody = SKPhysicsBody(texture: player.texture!, size: player.size)
            player.physicsBody?.categoryBitMask = PhysicsCategory.player
            player.physicsBody?.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.xp | PhysicsCategory.bossBeam | PhysicsCategory.border | PhysicsCategory.bossArenaBorder
            player.physicsBody?.collisionBitMask = PhysicsCategory.border | PhysicsCategory.bossArenaBorder
            player.physicsBody?.affectedByGravity = false
            player.physicsBody?.allowsRotation = false
            player.physicsBody?.isDynamic = true
            addChild(player)
            
            let crossbowNode = SKSpriteNode(imageNamed: "sk_crossbow")
            // The anchor point (0.5, 0) places the bottom of the sprite at the node's position
            crossbowNode.anchorPoint = CGPoint(x: 0.5, y: 0.0)
            crossbowNode.position = CGPoint(x: 0, y: player.size.height * -0.32)
            crossbowNode.zPosition = player.zPosition + 1
            crossbowNode.zRotation = .pi / -1.75
            player.addChild(crossbowNode)
            self.crossbowNode = crossbowNode
            
            //Initialize blades container
            bladesContainer = SKNode()
            bladesContainer?.position = CGPoint.zero
            bladesContainer?.zPosition = 1
            bladesContainer?.name = "bladesContainer"
            camera?.addChild(bladesContainer!)
            
            //Initialize barrier container
            barrierContainer = SKNode()
            barrierContainer?.position = CGPoint.zero
            barrierContainer?.zPosition = 2
            barrierContainer?.name = "barrierContainer"
            camera?.addChild(barrierContainer!)
            
            shieldContainer = SKNode()
            shieldContainer?.position = CGPoint.zero
            shieldContainer?.zPosition = 3
            shieldContainer?.name = "shieldContainer"
            camera?.addChild(shieldContainer!)
            
            //Player label above head
            let playerLabel = SKLabelNode(fontNamed: "Arial")
            playerLabel.text = "Player"
            playerLabel.fontSize = 20
            playerLabel.fontColor = .black
            playerLabel.position = CGPoint(x: 0, y: player.size.height / 2 + 30)
            playerLabel.name = "playerLabel"
//            player.addChild(playerLabel)
        }

        
//        TEST 'HARDSET' VALUES FOR BLADE
//        playerState.spinningBladesCount = 2
//        playerState.spinningBladesDamage = 3
//        playerState.spinningBladesSpeed = 1.0
//        skillManager.acquireOrUpgradeRegularSkill(
//            RegularSkill(definition: skillManager.allRegularDefinitions.first { $0.type == .spinningBlades }!)
//        )
//        playerState.barrierSize = 1000
////        playerState.barrierDamage = 1
//        playerState.barrierPulseFrequency = 2.0
//        skillManager.acquireOrUpgradeRegularSkill(
//            RegularSkill(definition: skillManager.allRegularDefinitions.first { $0.type == .protectiveBarrier }!))
        
        
        // Sets up lives label displaying playerLives
        if playerLivesLabel == nil {
            playerLivesLabel = SKLabelNode(fontNamed: "Arial")
            playerLivesLabel.fontSize = 20
            playerLivesLabel.fontColor = .black
            playerLivesLabel.position = CGPoint(x: -size.width / 2 + 80, y: size.height / 2 - 180)
            playerLivesLabel.zPosition = 5
        }
        playerLives = playerState.baseMaxHealth // Reset playerLives  
        
        setupTopOverlay()
        
        // Set up score label at the top
        if scoreLabel == nil {
            scoreNode = SKSpriteNode(imageNamed: "sk_score_node")
            scoreNode.position = CGPoint(x: size.width * -0.45 + scoreNode.size.width / 2, y: size.height * 0.43 - scoreNode.size.height / 2)
            scoreNode.zPosition = 6 // Above the overlay
            
            // This label only shows the number
            scoreLabel = SKLabelNode(fontNamed: "InknutAntiqua-ExtraBold")
            scoreLabel.fontSize = 16
            scoreLabel.fontColor = .black
            scoreLabel.position = CGPoint(x: 0, y: scoreNode.size.height * -0.35 - scoreLabel.frame.height)
            scoreLabel.zPosition = 7
            
            scoreNode.addChild(scoreLabel)
        }
        score = 0
        
        //Set up wave label at the top
        if waveLabel == nil {
            waveNode = SKSpriteNode(imageNamed: "sk_wave_node")
            waveNode.position = CGPoint(x: size.width * 0.45 - waveNode.size.width / 2, y: size.height * 0.43 - waveNode.size.height / 2)
            waveNode.zPosition = 6 // Above the overlay
            
            // This label only shows the wave number
            waveLabel = SKLabelNode(fontNamed: "InknutAntiqua-ExtraBold")
            waveLabel.fontSize = 16
            waveLabel.fontColor = .black
            waveLabel.position = CGPoint(x: 0, y: waveNode.size.height * -0.35 - waveLabel.frame.height)
            waveLabel.zPosition = 7
            
            waveNode.addChild(waveLabel)
        }
        //Set up progress label at the top
        if progressLabel == nil {
            progressLabel = SKLabelNode(fontNamed:"Arial")
            progressLabel.fontSize = 20
            progressLabel.fontColor = .black
            progressLabel.position = CGPoint(x: 0, y: size.height / 2 - 130)
            progressLabel.zPosition = 5
        }
        
        //Displaying upgrade stats label
        if upgradeStatsLabel == nil {
            upgradeStatsLabel = SKLabelNode(fontNamed: "Arial")
            upgradeStatsLabel.fontSize = 12
            upgradeStatsLabel.fontColor = .black
            upgradeStatsLabel.position = CGPoint(x: 0, y: player.size.height / 2 + 50)
//            player.addChild(upgradeStatsLabel)
        }
        updateUpgradeStatsLabel()
                
        // Clear any existing enemies
        wizardBoss?.isAlive = false
        childNode(withName: "wizard")?.removeFromParent()
        removeZombies()
        
        //Clear any existing boundaries/barriers from boss
        if let arenaOutline = self.childNode(withName: "arenaOutline") {
            arenaOutline.removeFromParent()
        }
        if let arenaBarrier = self.childNode(withName: "arenaBarrier") {
            arenaBarrier.removeFromParent()
        }

        //Wave function
        //maintainEnemyCount()
        initializeWaves()
        startNextWave()
        
        //Set up joystick
        if joystick == nil {
            joystick = ZPJoystick(baseRadius: 50, knobRadius: 25)
            joystick.position = CGPoint(x: -size.width / 2 + 100, y: -size.height / 2 + 100)
            joystick.zPosition = 5
            //cameraNode?.addChild(joystick)
        }
        
        //Set up shooting joystick
        if shootJoystick == nil {
            shootJoystick = ZPJoystick(baseRadius: 50, knobRadius: 25)
            shootJoystick.position = CGPoint(x: size.width / 2 - 100, y: -size.height / 2 + 100)
            shootJoystick.zPosition = 5
            //cameraNode?.addChild(shootJoystick)
        }
        updateUpgradeStatsLabel()
        
        let xpBar = XPBarNode(width: 150, height: 20)
        xpBar.position = CGPoint(x: 0, y: size.height * 0.35)
        xpBar.zPosition = 6
        camera?.addChild(xpBar)
        self.xpBarNode = xpBar
        startXPSpawnTimer()
    }
    
    func setupTopOverlay() {
        guard let cameraNode = self.camera else { return }
        
        // Create a semi-opaque black rectangle covering the top 1/6 of the screen
        let overlayHeight = size.height / 5.5
        let overlayRect = CGRect(
            x: -size.width / 2,
            y: size.height/2 - overlayHeight,
            width: size.width,
            height: overlayHeight
        )
        
        topOverlayNode = SKShapeNode(rect: overlayRect)
        topOverlayNode.fillColor = .black
        topOverlayNode.alpha = 0.4
        topOverlayNode.strokeColor = .clear
        topOverlayNode.zPosition = 5
    }
    
    // MARK: - Player Flash Effect

    /// Triggers a flashing red effect to indicate the player has taken damage.
    public func flashPlayer() {
        // Prevent overlapping flash animations
        guard !isPlayerFlashing else { return }
        isPlayerFlashing = true
        
        // Define the flash color and duration
        let flashColor = SKColor.red
        let flashDuration: TimeInterval = 0.2
        
        // Create color change actions
        let colorizeToFlash = SKAction.colorize(with: flashColor, colorBlendFactor: 1.0, duration: 0.05)
        let colorizeBack = SKAction.colorize(with: .white, colorBlendFactor: 0.0, duration: 0.05)
        
        // Sequence of flashing
        let flashSequence = SKAction.sequence([colorizeToFlash, colorizeBack])
        
        // Repeat the flash sequence a few times for a more noticeable effect
        let repeatFlash = SKAction.repeat(flashSequence, count: 1)
        
        // Completion action to reset the flashing flag
        let completion = SKAction.run { [weak self] in
            self?.isPlayerFlashing = false
            self?.player.colorBlendFactor = 0.0
        }
        
        // Run the flash sequence followed by the completion
        player.run(SKAction.sequence([repeatFlash, completion]))
    }
    
    func pauseGame() {
        guard !isGamePaused else { return }
        isGamePaused = true
        
        enemyManager.pauseAll()
        waveTransitionTimer?.pause()
        stopXPSpawnTimer()
        
        player.physicsBody?.velocity = .zero
    }
    
    func unpauseGame() {
        guard isGamePaused else { return }
        isGamePaused = false
        
        enemyManager.resumeAll()
        waveTransitionTimer?.resume()
        startXPSpawnTimer()
        
        for xpNode in xpNodesToRemove {
            self.playerState.currentXP += xpNode.xpAmount
            self.upgradeShopManager.incrementXPCount()
            self.updateXPBar()
            xpNode.removeFromParent()
        }
        
        // If you have any labels or banners currently showing that should vanish soon after resume,
        // you can find them and run a fade-out.
        if let cameraNode = self.camera {
            if !waveMessageLabel.isHidden {
                waveMessageLabel.removeAllActions()
                let fadeOut = SKAction.sequence([
                    SKAction.wait(forDuration: 2.0),
                    SKAction.fadeOut(withDuration: 0.5),
                    SKAction.run { [weak self] in self?.waveMessageLabel.isHidden = true }
                ])
                waveMessageLabel.run(fadeOut)
            }

            for banner in cameraNode.children where banner.name == "banner" {
                banner.removeAllActions()
                let fadeOut = SKAction.sequence([
                    SKAction.wait(forDuration: 2.0),
                    SKAction.fadeOut(withDuration: 0.5),
                    SKAction.removeFromParent()
                ])
                banner.run(fadeOut)
            }
        }
    }
    
    func initializeWaves() {
        //Define waves 1 through 7
        waveCycle = [
            Wave(waveNumber: 1, totalEnemies: 1, regularEnemies: 1, chargerEnemies: 0, exploderEnemies: 0, isHorde: false, isBoss: false, spawnInterval: 3.0, requiresFullClearance: false),
            Wave(waveNumber: 2, totalEnemies: 1, regularEnemies: 1, chargerEnemies: 0, exploderEnemies: 0, isHorde: false, isBoss: false, spawnInterval: 2.8, requiresFullClearance: false),
            Wave(waveNumber: 3, totalEnemies: 1, regularEnemies: 1, chargerEnemies: 0, exploderEnemies: 0, isHorde: true, isBoss: false, spawnInterval: 1.0, requiresFullClearance: false),
            Wave(waveNumber: 4, totalEnemies: 1, regularEnemies: 1, chargerEnemies: 0, exploderEnemies: 0, isHorde: false, isBoss: false, spawnInterval: 2.3, requiresFullClearance: false),
            Wave(waveNumber: 5, totalEnemies: 1, regularEnemies: 1, chargerEnemies: 0, exploderEnemies: 0, isHorde: false, isBoss: false, spawnInterval: 2.1, requiresFullClearance: false),
            Wave(waveNumber: 6, totalEnemies: 1, regularEnemies: 1, chargerEnemies: 0, exploderEnemies: 0, isHorde: true, isBoss: false, spawnInterval: 1.0, requiresFullClearance: true),
            Wave(waveNumber: 7, totalEnemies: 1, regularEnemies: 0, chargerEnemies: 0, exploderEnemies: 0, isHorde: false, isBoss: true, spawnInterval: 0.0, requiresFullClearance: false)
        ]
    }
    
    func startNextWave() {
        guard currentWaveIndex < waveCycle.count else {
            //All waves in the cycle completed, restart cycle with increased difficulty
            restartCycleWithIncreasedDifficulty()
            return
        }
        
        waveCounter += 1
        
        let wave = waveCycle[currentWaveIndex]
        pendingEnemies += wave.totalEnemies
        enemiesToSpawn += wave.totalEnemies
        updateProgressLabel()
        
        isTransitioningWave = true
        
        //Display wave start message
        if wave.isBoss {
            // Use the boss warning image
            showBannerNode(imageName: "sk_boss_warning", duration: 3.0)
        } else if wave.isHorde {
            // Use the horde incoming image
            showBannerNode(imageName: "sk_horde_incoming", duration: 3.0)
        } else {
            // Normal wave start message can remain text-based or also be replaced.
            // If you want to keep text-based messages for normal waves:
//            waveMessageLabel.text = "Wave \(waveCounter) starting.."
//            waveMessageLabel.fontSize = 30
//            waveMessageLabel.position = CGPoint(x: 0, y: size.height * 0.3)
//            waveMessageLabel.zPosition = 5
//            waveMessageLabel.isHidden = false
//
//            // Hide it after a short delay
//            let hideAction = SKAction.sequence([
//                SKAction.wait(forDuration: 3.0),
//                SKAction.run { [weak self] in self?.waveMessageLabel.isHidden = true }
//            ])
//            self.run(hideAction)
        }

        // Check for new enemy messages and show corresponding banners
        if let enemyMessage = newEnemyMessages[wave.waveNumber], !displayedEnemyMessages.contains(wave.waveNumber) {
            // Instead of using text, we use banner nodes:
            // Determine if we have a charger or exploder message
            if enemyMessage.contains("Charger") {
                // Show charger banner
                showBannerNode(imageName: "sk_charger_banner", duration: 5.0)
            } else if enemyMessage.contains("Exploder") {
                // Show exploder banner
                showBannerNode(imageName: "sk_exploder_banner", duration: 5.0)
            }
            displayedEnemyMessages.insert(wave.waveNumber)
        }
        
//        print("-")
//        print("wave", wave)
        if wave.isBoss {
            clearAllEnemies() //Clear existing enemies only for boss waves
            startBossStage()
            
        } else {
            //Regular wave: do not clear existing enemies
            removeAction(forKey: "spawnNextEnemy")
            //FIGURE OUT THIS BELOW TO MAKE MESSAGES WORK
            waveMessageLabel.isHidden = true
            isTransitioningWave = false
            spawnNextEnemy()
        }
        
    }
    
    func showBannerNode(imageName: String, duration: TimeInterval = 4.0) {
        guard let cameraNode = self.camera else { return }
        let banner = SKSpriteNode(imageNamed: imageName)
        // Position banner at a suitable place; adjust as needed
        banner.position = CGPoint(x: 0, y: size.height * 0.22)
        banner.zPosition = 5
        banner.alpha = 0.0
        banner.name = "banner"
        cameraNode.addChild(banner)
        
        let fadeIn = SKAction.fadeIn(withDuration: 0.5)
        
        let pulseIn = SKAction.scale(to: 1.03, duration: 1.0)
        let pulseOut = SKAction.scale(to: 1.0, duration: 1.0)
        let pulseSequence = SKAction.sequence([pulseOut, pulseIn])
        let pulse = SKAction.repeat(pulseSequence, count: 2)
        
        let sequence = SKAction.sequence([
            fadeIn,
            pulse,
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent()
        ])
        
        
        banner.run(sequence)
    }
    
    
    func spawnNextEnemy() {
        guard currentWaveIndex < waveCycle.count else { return }
        var wave = waveCycle[currentWaveIndex]
        
        // Check if all enemies have been spawned
        if wave.allEnemiesSpawned {
            handleWaveProgression()
            waveCycle[currentWaveIndex] = wave // Update the wave with new spawn counts
            return
        }
        
        // Decide which enemy to spawn next
        let spawnDecision = decideNextEnemyType(for: wave)
        
        switch spawnDecision {
        case .regular:
            spawnZombies(withHealth: zombieHealth)
            wave.spawnedRegular += 1
        case .charger:
            spawnChargerZombie()
            wave.spawnedCharger += 1
        case .exploder:
            spawnExploderZombie()
            wave.spawnedExploder += 1
        }
        
        // Update the wave in the cycle
        waveCycle[currentWaveIndex] = wave
        
        //Decrement enemiesToSpawn as an enemy has been spawned
        enemiesToSpawn -= 1
        
        // Schedule the next enemy spawn
        let currentWaveObject = waveCycle[currentWaveIndex]
        if currentWaveObject.spawnInterval > 0 {
            let spawnAction = SKAction.run { [weak self] in
                self?.spawnNextEnemy()
            }
            let waitAction = SKAction.wait(forDuration: currentWaveObject.spawnInterval)
            let sequence = SKAction.sequence([waitAction, spawnAction])
            run(sequence, withKey: "spawnNextEnemy")
        }
        updateProgressLabel()
    }
    
    enum EnemyType {
        case regular
        case charger
        case exploder
    }

    func decideNextEnemyType(for wave: Wave) -> EnemyType {
        var possibleTypes: [EnemyType] = []
        
        if wave.spawnedRegular < wave.regularEnemies {
            possibleTypes.append(.regular)
        }
        if wave.spawnedCharger < wave.chargerEnemies {
            possibleTypes.append(.charger)
        }
        if wave.spawnedExploder < wave.exploderEnemies {
            possibleTypes.append(.exploder)
        }
        
        // Randomly select one of the possible types
        return possibleTypes.randomElement() ?? .regular
        //return .regular
    }

    
    func spawnEnemyTypes(regular: Int, charger: Int, exploder: Int) {
        for _ in 0..<regular {
            spawnZombies(withHealth: zombieHealth)
        }
        for _ in 0..<charger {
            spawnChargerZombie()
        }
        for _ in 0..<exploder {
            spawnExploderZombie()
        }
    }
    
    func updateProgressLabel() {
        if isBossStage {
            progressLabel.text = "Defeat the boss!"
        }
        else if pendingEnemies > 0 {
            progressLabel.text = "Enemies left: \(pendingEnemies)"
        }
        else {
            progressLabel.text = "Waiting for next wave..."
        }
    }
    
    func showUpgradeShopOverlay(with choices: [RegularSkill]) {
        let overlaySize = CGSize(width: size.width, height: size.height)
        let upgradeOverlay = UpgradeShopOverlayNode(choices: choices, manager: upgradeShopManager, overlayManager: overlayManager, skillManager: skillManager, overlaySize: overlaySize)
        overlayManager.enqueueOverlay(upgradeOverlay)
    }
    
    //MARK: - PlayerStateDelegate Methods
    
    //REGULAR SKILLS
    func playerStateDidAddSpinningBlades(_ state: PlayerState) {
        guard let bladesContainer = bladesContainer else { return }
        
        // Remove existing blades
        bladesContainer.removeAllChildren()
        
        // Define blade properties
        let bladeTexture = SKTexture(imageNamed: "sk_spinning_blades")
        let bladeSize = bladeTexture.size()
        let bladeColor = SKColor.green
        
        // Calculate the angle between each blade
        let bladeCount = state.spinningBladesCount
        guard bladeCount > 0 else { return }
        let angleIncrement = (2 * CGFloat.pi) / CGFloat(bladeCount)
        
        // Define the radius at which blades orbit
        let orbitRadius: CGFloat = 75.0 // Adjust as needed
        
        // Create and position each blade
        for i in 0..<bladeCount {
            let blade = SKSpriteNode(texture: bladeTexture)
            blade.size = bladeSize
            blade.setScale(0.6)
            blade.name = "spinningBlade"
            
            blade.physicsBody = SKPhysicsBody(rectangleOf: bladeSize)
            blade.physicsBody?.categoryBitMask = PhysicsCategory.blade
            blade.physicsBody?.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.boss | PhysicsCategory.exploder
            blade.physicsBody?.collisionBitMask = PhysicsCategory.none
            blade.physicsBody?.affectedByGravity = false
            blade.physicsBody?.allowsRotation = false
            blade.physicsBody?.isDynamic = false
            
            // Calculate the position of the blade around the container
            let angle = CGFloat(i) * angleIncrement
            let xPosition = orbitRadius * cos(angle)
            let yPosition = orbitRadius * sin(angle)
            blade.position = CGPoint(x: xPosition, y: yPosition)
            
            bladesContainer.addChild(blade)
        }
        
        // Remove any existing rotation action
        bladesContainer.removeAction(forKey: "rotate")
        
        // Define rotation speed
        let baseDuration: TimeInterval = 0.5
        let rotationDuration = baseDuration / state.spinningBladesSpeed
        
        // Create a rotation action
        let rotateAction = SKAction.rotate(byAngle: CGFloat.pi * 2, duration: rotationDuration)
        let repeatRotate = SKAction.repeatForever(rotateAction)
        
        // Run the rotation action on the container
        bladesContainer.run(repeatRotate, withKey: "rotate")
        
    }

    
    func playerStateDidUpgradeBarrier(_ state: PlayerState) {
        guard let barrierContainer = barrierContainer else { return }
        
        //Remove existing barrier
        barrierContainer.removeAllChildren()
        
        //Define barrier properties
        let barrierRadius: CGFloat = 20.0 + state.barrierSize   // CAN CHANGE
        let barrierColor = UIColor(hex: "#B5BFFF")?.withAlphaComponent(0.1) // Semi-transparent blue
        let strokeColor = UIColor(hex: "#2500C9")?.withAlphaComponent(0.1) // Semi-transparent blue
        
        //Create barrier shape
        let barrier = SKShapeNode(circleOfRadius: barrierRadius)
        barrier.name = "protectiveBarrier"
        
        barrier.physicsBody = SKPhysicsBody(circleOfRadius: barrierRadius)
        barrier.physicsBody?.categoryBitMask = PhysicsCategory.protectiveBarrier
        barrier.physicsBody?.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.boss | PhysicsCategory.exploder
        barrier.physicsBody?.collisionBitMask = PhysicsCategory.none
        barrier.physicsBody?.affectedByGravity = false
        barrier.physicsBody?.allowsRotation = false
        barrier.physicsBody?.isDynamic = false
        
        barrier.fillColor = barrierColor ?? .blue.withAlphaComponent(0.1)
        barrier.strokeColor = strokeColor ?? .blue.withAlphaComponent(0.1)
        barrier.lineWidth = 3.0
        barrier.zPosition = player.zPosition - 1 // CURRENTLY ABOVE BLADES. Can change.
        barrier.position = CGPoint.zero
        
        let boltNode = SKSpriteNode(imageNamed: "sk_protective_bolt")
        boltNode.position = CGPoint(x: 0, y: barrier.frame.height * -0.025)
        boltNode.zPosition = barrier.zPosition
        boltNode.alpha = 0.1
        let scale = (barrier.frame.height * 0.7) / boltNode.size.height
        boltNode.setScale(scale)
        barrier.addChild(boltNode)
        
        //Create pulsing action
        let pulseUp = SKAction.scale(to: 1.2, duration: 1.0 - state.barrierPulseFrequency) // CAN CHANGE
        let pulseDown = SKAction.scale(to: 1.0, duration: 1.0 - state.barrierPulseFrequency) // CAN CHANGE
        let pulseSequence = SKAction.sequence([pulseUp, pulseDown])
        let repeatPulse = SKAction.repeatForever(pulseSequence)
        barrier.run(repeatPulse)
        
        //Add barrier to the barrierContainer
        barrierContainer.addChild(barrier)
        
    }
        
    func playerStateDidUpgradeHealth(_ state: PlayerState, restorePercentage: Double) {
        //
    }
    
    func restoreHealth(_ restorePercentage: Double) {
        let restorationAmount = playerState.currentMaxHealth * restorePercentage
        playerLives = min(playerLives + restorationAmount, playerState.currentMaxHealth)
    }
    
    func playerStateDidUpgradeMagnet(_ state: PlayerState) {
        // Only need this if we add UI effects after activation
        print("Magnet Radius increased!")
    }
    
    func playerStateDidUpgradeFreeze(_ state: PlayerState) {
        // Only need this if we add UI effects after activation
        print("Freeze Grenade Activated!")
    }
    
    // SPECIAL SKILLS
    func playerStateDidActivateHelpingHand(_ state: PlayerState) { /// ACTIVATE
        //Start firing additional projectiles every 4 seconds
        let fireAction = SKAction.run { [weak self] in
            self?.fireHelpingHandProjectile()
        }
        let waitAction = SKAction.wait(forDuration: 2.0)
        let sequence = SKAction.sequence([fireAction, waitAction])
        let repeatForever = SKAction.repeatForever(sequence)
        run(repeatForever, withKey: "helpingHandFire")
    }
    
    func playerStateDidDeactivateHelpingHand() { /// DEACTIVATE
        removeAction(forKey: "helpingHandFire")
    }
    
    func playerStateDidActivateReinforcedArrow(_ state: PlayerState) {
        // Only need this if we add UI effects after activation
        print("Reinforced Arrow activated!")
    }
    
    func playerStateDidActivateSpectralShield(_ state: PlayerState) { /// ACTIVATE
        addSpectralShield()
    }
    
    func playerStateDidDeactivateSpectralShield() { /// DEACTIVATE
        removeSpectralShield()
    }
    
    func playerStateDidActivateMightyKnockback(_ state: PlayerState) {
        print("Mightyknockback activated!")
        activateMightyKnockback()
    }
    
    func playerStateDidDeactivateMightyKnockback() {
        deactivateMightyKnockback()
    }
    
    func playerStateDidActivateBonusHealth(_ state: PlayerState, restorePercentage: Double) {
        // Restores player HP back to full health
        //
    }
    
    func activateHelpingHand() {
        playerState.hasHelpingHand = true
    }
    
    func removeZombies() {
        for zombie in enemyManager.enemies {
            zombie.removeFromParent()
        }
        enemyManager.enemies.removeAll()
    }

    func spawnZombies(withHealth health: Double) {
        enemyManager.spawnRegularZombie(health: health)
    }
    
    func spawnChargerZombie() {
        enemyManager.spawnChargerZombie(health: zombieHealth, speed: zombieSpeed)
    }
        
    func spawnExploderZombie() {
        enemyManager.spawnExploderZombie(health: zombieHealth, speed: zombieSpeed)
    }
    
    func checkAndRespawnZombies(respawnRadius: CGFloat) {
        for zombie in enemyManager.enemies {
            let distanceFromPlayer = zombie.position.distance(to: player.position)
            
            if distanceFromPlayer > respawnRadius {
                let safeRadius: CGFloat = 150.0
                let spawnDistance: CGFloat = 250.0
                
                var newPosition: CGPoint
                repeat {
                    let angle = CGFloat.random(in: 0...2 * .pi)
                    newPosition = CGPoint(
                        x: player.position.x + spawnDistance * cos(angle),
                        y: player.position.y + spawnDistance * sin(angle)
                    )
                } while newPosition.distance(to: player.position) < safeRadius || enemyManager.enemies.contains(where: { $0 !== zombie && $0.frame.contains(newPosition) })
                //Update the zombie's position
                zombie.position = newPosition
            }
        }
    }
    
    func spawnWizardBoss() {
        waveTransitionTimer?.callback = {}
        
        teleportPlayerToCenter { [weak self] in
            guard let self = self else { return }
            guard let cameraNode = self.camera else { return }
            let cameraCenter = cameraNode.position
            //cameraNode.position = self.player.position
            
            arenaBounds = CGRect(
                x: cameraCenter.x - size.width / 2,
                y: cameraCenter.y - size.height / 2,
                width: size.width - 75,
                height: size.height - 200
            )
            
            if let arenaBounds = arenaBounds {
                let outline = SKShapeNode(rectOf: CGSize(width: arenaBounds.width, height: arenaBounds.height))
                outline.position = CGPoint(x: arenaBounds.midX, y: arenaBounds.midY)
                outline.strokeColor = .purple
                outline.fillColor = .clear
                outline.lineWidth = 2.0
                outline.name = "arenaOutline"
                addChild(outline)
            }
            
            setupArenaBarrier()
            
            //Define boss spawn position outside the arena
            let spawnOffsetY: CGFloat = 100.0
            let spawnY = arenaBounds!.maxY + spawnOffsetY
            let spawnX = arenaBounds!.minX
            let spawnPosition = CGPoint(x: spawnX, y: spawnY)
            
            wizardBoss?.isAlive = true
            enemyManager.spawnWizardBoss(health: wizardHealth, at: spawnPosition)
        }
        
    }
    
    func teleportPlayerToCenter(completion: (() -> Void)? = nil) {
        //Define the center position. Can adjust to any other point too.
        let centerPosition = CGPoint(x: size.width / 2, y: size.height / 2 - 700)
        
        //Optional fade effect - test
        let fadeOut = SKAction.fadeOut(withDuration: 0.2)
        let fadeIn = SKAction.fadeIn(withDuration: 0.2)
        let teleport = SKAction.run { [weak self] in
            self?.player.position = centerPosition
        }
        let sequence = SKAction.sequence([fadeOut, teleport, fadeIn])
        
        //Run the action sequence
        self.run(sequence) {
            //Call the completion handler after teleportation
            completion?()
        }
    }
    
    func updateCamera() {
        guard let cameraNode = self.camera else { return }
        if arenaBounds == nil {
            //Normal camera-follow behavior
            cameraNode.position = CGPoint(
                x: player.position.x,
                y: player.position.y
            )
        } else {
            //Lock camera at arena's center for when boss spawn
//            cameraNode.position = CGPoint(
//                x: arenaBounds!.midX,
//                y: arenaBounds!.midY
//            )
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let cameraNode = self.camera else { return }
        
        // MARK: NEW OVERLAY
         // If there's currently an overlay shown, we handle touches there
        if let overlay = cameraNode.children.first(where: { $0 is UpgradeShopOverlayNode || $0 is BossSpinnerOverlayNode }) {
            if let spinnerOverlay = overlay as? BossSpinnerOverlayNode {
                for touch in touches {
                    let location = touch.location(in: cameraNode)
                    spinnerOverlay.touchBegan(at: location)
                }
                return
            } else if let upgradeOverlay = overlay as? UpgradeShopOverlayNode {
                for touch in touches {
                    let location = touch.location(in: cameraNode)
                    upgradeOverlay.touchBegan(at: location)
                }
                return
            }
        }
        
        for touch in touches {
            let touchLocationInCamera = touch.location(in: cameraNode)

            // Handle joystick interactions
            if joystick.contains(touchLocationInCamera) && activeTouches[touch] == nil && !gameOver {
                joystick.startTouch(at: touch.location(in: joystick))
                activeTouches[touch] = joystick
            } else if shootJoystick.contains(touchLocationInCamera) && activeTouches[touch] == nil && !gameOver {
                shootJoystick.startTouch(at: touch.location(in: shootJoystick))
                shootJoystick.activate()
                activeTouches[touch] = shootJoystick
            }

            // Handle game-over interactions
            if gameOver {
                if let gameOverNode = cameraNode.childNode(withName: "gameOverScreen") {
                    let touchLocationInGameOver = touch.location(in: gameOverNode)
                    let tappedNodes = gameOverNode.nodes(at: touchLocationInGameOver)
                    for node in tappedNodes {
                        if node.name == "retryButton" {
                            restartGame()
                            return
                        } else if node.name == "leaderboardButton" {
                            //LEADERBOARDS LOGIC HERE
                        } else if node.name == "mainMenuButton" {
                            //MAIN MENU LOGIC HERE
                        }
                    }
                }
                return //Stops interaction while gameover screen is active
            }
        }
    }


    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let joystick = activeTouches[touch] {
                let location = touch.location(in: joystick)
                joystick.moveTouch(to: location)
            }
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let joystick = activeTouches[touch] {
                joystick.endTouch()
                if joystick === shootJoystick {
                    shootJoystick.deactivate()
                }
                activeTouches[touch] = nil
            }
        }
    }
    
    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        currentGameTime = currentTime
        
        camera?.position = player.position
//        updateCamera()
    
        checkXPCollection()
        
        guard !gameOver, !isGamePaused else { return }
        
        mapManager.manageScrolling(playerPosition: player.position)
        
        checkAndRespawnZombies(respawnRadius: 400)
        applyContinuousDamage(currentTime: currentGameTime)
        

        
        if playerLives <= 0 {
            showGameOverScreen()
            return
        }
        
        //Update shooting progress bar
        let timeSinceLastShot = currentGameTime - lastShootTime
        let attackSpeed = playerState.currentAttackSpeed > 0 ? playerState.currentAttackSpeed : 2.0
        shootingProgress = CGFloat(timeSinceLastShot / attackSpeed)
        shootingProgress = min(shootingProgress, 1.0) // Clamp to 1.0
        
        // Calculate time delta for consistent movement
        let deltaTime = currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        updatePlayerVelocity()
        
        let aimDirection = shootJoystick.positionDelta
        // Only update facing if there's a noticeable direction
        if abs(aimDirection.x) > 0.1 || abs(aimDirection.y) > 0.1 {
            // Calculate angle from aim direction
            let angle = atan2(aimDirection.y, aimDirection.x) - CGFloat.pi / 2
            
            // Rotate the crossbow to face aim direction
            crossbowNode.zRotation = angle
        }
        
        //Check shoot joystick to aim and shoot projectiles
        if shootJoystick.isActive {
            let aimDirection = shootJoystick.positionDelta
            if aimDirection != .zero && currentTime - lastShootTime >= playerState.currentAttackSpeed{
                shootingProgress = 0.0
                lastShootTime = currentTime
                shootProjectile(in: aimDirection)
                
                if playerState.freezeGrenadeActive {
                    let freezeGrenadeInterval = playerState.freezeGrenadeBaseCooldown - playerState.freezeGrenadeCooldownReduction
                    if  currentTime - lastGrenadeTime >= freezeGrenadeInterval {
                        lastGrenadeTime = currentTime
                        shootGrenade(in: aimDirection)
                    }
                }
            }
        }
        
        
        enemyManager.updateEnemies(currentTime: currentTime, deltaTime: deltaTime, playerPosition: player.position)
        
        if currentWaveIndex < waveCycle.count {
            let wave = waveCycle[currentWaveIndex]
            if wave.allEnemiesSpawned && pendingEnemies <= 0 && !isBossStage {
                handleWaveProgression()
            }
        }
        
    }
    
    func updatePlayerVelocity() {
        let maxVelocity = playerState.currentMovementSpeed
        let inputVector = joystick.positionDelta
        let desiredVelocity = CGVector(dx: inputVector.x * maxVelocity, dy: inputVector.y * maxVelocity)
        player.physicsBody?.velocity = desiredVelocity
        
        if desiredVelocity.dx < -0.1 {
            player.texture = SKTexture(imageNamed: "sk_player_left")
        } else if desiredVelocity.dx > 0.1 {
            player.texture = SKTexture(imageNamed: "sk_player_right")
        }
    }
    
    
    func countActiveChargers() -> Int {
        return enemyManager.enemies.filter { $0 is ZPChargerZombieNode }.count
    }
    func countActiveExploders() -> Int {
        return enemyManager.enemies.filter { $0 is ZPExploderZombieNode }.count
    }
    
    func handleWaveProgression() {
        guard !isTransitioningWave else { return }
        isTransitioningWave = true
        
        //Start grace period timer
//        waveMessageLabel.text = "Wave Over. Defeat remaining enemies.."
//        waveMessageLabel.fontSize = 20
//        waveMessageLabel.position = CGPoint(x: 0, y: size.height * 0.3)
//        waveMessageLabel.zPosition = 5
//        waveMessageLabel.isHidden = false
        
        isGracePeriodActive = true
        remainingGracePeriod = gracePeriod
        
        waveTransitionTimer = PausableTimer(interval: gracePeriod, repeats: false) { [weak self] in
            self?.afterGracePeriodEnds()
        }
        waveTransitionTimer?.start()
        
//        waveProgressionWorkItem = DispatchWorkItem { [weak self] in
//            guard let self = self else { return }
//            if self.waveCycle[currentWaveIndex].requiresFullClearance {
//                if self.pendingEnemies > 0 {
//                    //Do not proceed. Wait until all enemies are defeated
//                    self.waveMessageLabel.text = "Defeat all enemies to proceed.."
//                    self.waveMessageLabel.position = CGPoint(x: 0, y: size.height * 0.3)
//                    self.waveMessageLabel.zPosition = 5
//                } else {
//                    self.transitionToNextWave()
//                }
//            } else {
//                //Regular wave progression
//                if self.pendingEnemies > 0 {
//                    self.waveMessageLabel.text = "Next wave starting.."
//                    self.waveMessageLabel.position = CGPoint(x: 0, y: size.height * 0.3)
//                    self.waveMessageLabel.zPosition = 5
//                } else {
//                    self.waveMessageLabel.text = "Wave Cleared. Next wave starting.."
//                    self.waveMessageLabel.position = CGPoint(x: 0, y: size.height * 0.3)
//                    self.waveMessageLabel.zPosition = 5
//                }
//                self.transitionToNextWave()
//            }
//            self.waveMessageLabel.isHidden = false
//        }
//        //Schedule the wave progression after graceperiod
//        if let workItem = waveProgressionWorkItem {
//            DispatchQueue.main.asyncAfter(deadline: .now() + gracePeriod, execute: workItem)
//        }
    }
    
    func transitionToNextWave() {
        self.currentWaveIndex += 1
        if self.currentWaveIndex >= self.waveCycle.count {
            self.restartCycleWithIncreasedDifficulty()
        } else {
            //DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                //guard let self = self else { return }
            self.waveMessageLabel.isHidden = true
            self.isTransitioningWave = false
            self.startNextWave()
            //}
        }
    }
    
    func afterGracePeriodEnds() {
        waveTransitionTimer?.callback = {}
        
        if self.waveCycle[self.currentWaveIndex].requiresFullClearance {
            if self.pendingEnemies > 0 {
                // Do not proceed. Wait until all enemies are defeated
                self.waveMessageLabel.text = "Defeat all enemies to proceed.."
                self.waveMessageLabel.position = CGPoint(x: 0, y: size.height * 0.3)
                self.waveMessageLabel.zPosition = 5
                self.waveMessageLabel.isHidden = false
                // Maintain isGracePeriodActive and isTransitioningWave to prevent further progression
            } else {
                self.transitionToNextWave()
            }
        } else {
            // Regular wave progression
            if self.pendingEnemies > 0 {
                self.waveMessageLabel.text = "Next wave starting.."
                self.waveMessageLabel.position = CGPoint(x: 0, y: size.height * 0.3)
                self.waveMessageLabel.zPosition = 5
            } else {
                self.waveMessageLabel.text = "Wave Cleared. Next wave starting.."
                self.waveMessageLabel.position = CGPoint(x: 0, y: size.height * 0.3)
                self.waveMessageLabel.zPosition = 5
            }
            self.waveMessageLabel.isHidden = false
            self.transitionToNextWave()
        }

        // Reset wave progression status
        self.isGracePeriodActive = false
        self.isTransitioningWave = false
    }
    
    func clearAllEnemies() {
        enemyManager.removeAllEnemies()
    }
    
    
    func startBossStage() {
        print("startBossStage", currentWaveIndex, "<", waveCycle.count)
        guard currentWaveIndex < waveCycle.count else { return }
        let wave = waveCycle[currentWaveIndex]
        guard wave.isBoss else { return }
        
        isBossStage = true
        isTransitioningWave = true //Prevents regular enemy spawning during boss stage
        clearAllEnemies()
        
        progressLabel.text = "Defeat the boss!"
        waveMessageLabel.text = "Boss Stage Starting.."
        waveMessageLabel.isHidden = false
        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
//            self.waveMessageLabel.isHidden = true
//            self.isTransitioningWave = false
//            self.spawnWizardBoss()
//        }
        waveTransitionTimer = PausableTimer(interval: 3.0, repeats: false) { [weak self] in
            print("timer mark")
            self?.waveMessageLabel.isHidden = true
            self?.isTransitioningWave = false
            self?.spawnWizardBoss()
        }
        waveTransitionTimer?.start()
    }
    
    
    func setupArenaBarrier() {
        guard let arenaBounds = arenaBounds else { return }
        
        let arenaBarrier = SKSpriteNode(color: .clear, size: CGSize(width: arenaBounds.width, height: arenaBounds.height))
        arenaBarrier.position = CGPoint(x: arenaBounds.midX, y: arenaBounds.midY)
        arenaBarrier.name = "arenaBarrier"
        
        //Configure physics body as an edge loop to prevent the player from leaving
        arenaBarrier.physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(x: -arenaBounds.width / 2, y: -arenaBounds.height / 2, width: arenaBounds.width, height: arenaBounds.height))
        arenaBarrier.physicsBody?.categoryBitMask = PhysicsCategory.bossArenaBorder
        arenaBarrier.physicsBody?.contactTestBitMask = PhysicsCategory.player
        arenaBarrier.physicsBody?.collisionBitMask = PhysicsCategory.player
        arenaBarrier.physicsBody?.affectedByGravity = false
        arenaBarrier.physicsBody?.allowsRotation = false
        arenaBarrier.physicsBody?.isDynamic = false
        addChild(arenaBarrier)
    }
    
    func handleBossDefeat() {
        
        wizardBoss?.isAlive = false
        arenaBounds = nil

        if let outline = childNode(withName: "arenaOutline") as? SKShapeNode {
            outline.removeFromParent()
        }
        
         // Create the special skill spinner overlay
        let spinnerOverlay = BossSpinnerOverlayNode(skillManager: skillManager, overlayManager: overlayManager, overlaySize: size)
        overlayManager.enqueueOverlay(spinnerOverlay)
        
        isBossStage = false
        isTransitioningWave = true
        currentWaveIndex += 1 // Move to next wave in cycle
        waveLabel.text = "Wave \(waveCounter)"
        
        //No enemies to carry over from boss stage
        //pendingEnemies reset
        pendingEnemies = 0
        enemiesToSpawn = 0
        updateProgressLabel()
        
        //Increase difficulty variables
        zombieSpeed += 0.1
        zombieHealth += 3
        wizardHealth += 15
        gracePeriod = max(1.0, gracePeriod - 2.0) // Decrease grace period, minimum 5 seconds
        miniWaveInterval = max(1.0, miniWaveInterval - 0.1)
        
        //Show post boss message
        waveMessageLabel.text = "Enemies getting stronger.."
        waveMessageLabel.fontSize = 30
        waveMessageLabel.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.waveMessageLabel.isHidden = true
            self.waveMessageLabel.fontSize = 40
            self.isTransitioningWave = false // Allow regular spawning again
            self.startNextWave()
        }
    
    }
    
    func restartCycleWithIncreasedDifficulty() {
        print("restarting")
        //Remove existing waves
        waveCycle.removeAll()
        
        //Define increased difficulty waves
        //For simplicity, we'll increase the number of enemies and adjust spawn intervals
        //Can further customize here based on game's balance needs later on
        
        let cycleMultiplier = 2
        //*******************************************************************************************
        //*******************************************************************************************
        //*******************************************************************************************
        // SEE NOTE ABOVE ^
        
        for waveNumber in 1...7 {
            switch waveNumber {
            case 1:
                waveCycle.append(Wave(waveNumber: waveNumber, totalEnemies: 10 * Int(cycleMultiplier), regularEnemies: 10 * Int(cycleMultiplier), chargerEnemies: 0, exploderEnemies: 0, isHorde: false, isBoss: false, spawnInterval: 3.0 - 1.0, requiresFullClearance: false))
            case 2:
                waveCycle.append(Wave(waveNumber: waveNumber, totalEnemies: 15 * Int(cycleMultiplier), regularEnemies: 15 * Int(cycleMultiplier), chargerEnemies: 0, exploderEnemies: 0, isHorde: false, isBoss: false, spawnInterval: 2.8 - 1.0, requiresFullClearance: false))
            case 3:
                waveCycle.append(Wave(waveNumber: waveNumber, totalEnemies: 30 * Int(cycleMultiplier), regularEnemies: 30 * Int(cycleMultiplier), chargerEnemies: 0, exploderEnemies: 0, isHorde: true, isBoss: false, spawnInterval: 0.5, requiresFullClearance: false))
            case 4:
                waveCycle.append(Wave(waveNumber: waveNumber, totalEnemies: 35 * Int(cycleMultiplier), regularEnemies: 30 * Int(cycleMultiplier), chargerEnemies: 5 * Int(cycleMultiplier), exploderEnemies: 0, isHorde: false, isBoss: false, spawnInterval: 2.3 - 1.0, requiresFullClearance: false))
            case 5:
                waveCycle.append(Wave(waveNumber: waveNumber, totalEnemies: 40 * Int(cycleMultiplier), regularEnemies: 30 * Int(cycleMultiplier), chargerEnemies: 5 * Int(cycleMultiplier), exploderEnemies: 5 * Int(cycleMultiplier), isHorde: false, isBoss: false, spawnInterval: 2.1 - 1.0, requiresFullClearance: false))
            case 6:
                waveCycle.append(Wave(waveNumber: waveNumber, totalEnemies: 46 * Int(cycleMultiplier), regularEnemies: 30 * Int(cycleMultiplier), chargerEnemies: 8 * Int(cycleMultiplier), exploderEnemies: 8 * Int(cycleMultiplier), isHorde: true, isBoss: false, spawnInterval: 0.5, requiresFullClearance: true))
            case 7:
                waveCycle.append(Wave(waveNumber: waveNumber, totalEnemies: 1, regularEnemies: 0, chargerEnemies: 0, exploderEnemies: 0, isHorde: false, isBoss: true, spawnInterval: 0.0, requiresFullClearance: false))
            default:
                break
            }
        }
        currentWaveIndex = 0
        pendingEnemies = 0
        enemiesToSpawn = 0
        updateProgressLabel()
        startNextWave()
    }

    func shootProjectile(in direction: CGPoint) {
        let projectileTextureName = playerState.projectilesPierce ? "sk_arrow_reinforced" : "sk_arrow"

        let projectile = SKSpriteNode(imageNamed: projectileTextureName)
        projectile.setScale(0.3)
        projectile.position = player.position
        projectile.zPosition = player.zPosition - 1
        projectile.name = "projectile"
        projectile.userData = NSMutableDictionary()
        projectile.userData?.setValue(playerState.projectilesPierce, forKey: "pierce")
        
        projectile.physicsBody = SKPhysicsBody(texture: projectile.texture!, size: projectile.size)
        projectile.physicsBody?.categoryBitMask = PhysicsCategory.projectile
        projectile.physicsBody?.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.boss | PhysicsCategory.border | PhysicsCategory.exploder
        projectile.physicsBody?.collisionBitMask = PhysicsCategory.none
        projectile.physicsBody?.affectedByGravity = false
        projectile.physicsBody?.allowsRotation = false
        
        addChild(projectile)

        let normalizedDirection = CGVector(dx: direction.x, dy: direction.y).normalized
        projectile.zRotation = atan2(normalizedDirection.dy, normalizedDirection.dx) - CGFloat.pi / 2

        let moveDistance: CGFloat = playerState.currentRange
        let speed: CGFloat = playerState.projectileSpeed
        let duration = TimeInterval(moveDistance / speed)

        let moveAction = SKAction.move(by: CGVector(dx: normalizedDirection.dx * moveDistance,
                                                    dy: normalizedDirection.dy * moveDistance),
                                       duration: duration)

        let removeAction = SKAction.removeFromParent()
        projectile.run(SKAction.sequence([moveAction, removeAction]))
    }
    
    func shootGrenade(in direction: CGPoint) {
        let grenade = SKSpriteNode(imageNamed: "sk_freeze_grenade")
        grenade.setScale(0.4)
        grenade.position = player.position
        grenade.name = "freezeGrenade"
        grenade.userData = NSMutableDictionary()
        grenade.userData?["hasCollided"] = false
        
        // MARK: Physics
        grenade.physicsBody = SKPhysicsBody(texture: grenade.texture!, size: grenade.size)
//        grenade.physicsBody?.categoryBitMask = PhysicsCategory.projectile
//        grenade.physicsBody?.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.boss
        grenade.physicsBody?.categoryBitMask = PhysicsCategory.grenade
        grenade.physicsBody?.contactTestBitMask = PhysicsCategory.border
        grenade.physicsBody?.collisionBitMask = PhysicsCategory.none // Projectiles usually don't collide, just pass through
        grenade.physicsBody?.affectedByGravity = false
        grenade.physicsBody?.allowsRotation = false
        
        addChild(grenade)
        
        // Set up movement action in the specified direction
        let normalizedDirection = CGVector(dx: direction.x, dy: direction.y).normalized
        let grenadeMoveDistance: CGFloat = 150.0  // Example distance
        let moveAction = SKAction.move(by: CGVector(dx: normalizedDirection.dx * grenadeMoveDistance, dy: normalizedDirection.dy * grenadeMoveDistance), duration: 1.0)
        
        let waitAction = SKAction.wait(forDuration: 1.0)
        let explodeAction = SKAction.run {
            self.explodeGrenade(grenade)
        }
        let removeAction = SKAction.removeFromParent()
        let sequence = SKAction.sequence([moveAction, waitAction, explodeAction, removeAction])
        grenade.run(sequence)
            
    }
        
    func explodeGrenade(_ grenade: SKSpriteNode) {
        let explosionRadius = playerState.freezeRadius + 25.0
        
        let freezeExplosion = SKShapeNode(circleOfRadius: explosionRadius)
        freezeExplosion.position = grenade.position
        freezeExplosion.zPosition = 4
        
        freezeExplosion.fillColor = .cyan.withAlphaComponent(0.3)
        freezeExplosion.strokeColor = .cyan
        freezeExplosion.lineWidth = 1.0
        freezeExplosion.glowWidth = 2.0
        freezeExplosion.alpha = 0.0
        
        freezeExplosion.physicsBody = SKPhysicsBody(circleOfRadius: explosionRadius)
        freezeExplosion.physicsBody?.categoryBitMask = PhysicsCategory.freeze
        freezeExplosion.physicsBody?.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.boss | PhysicsCategory.exploder
        freezeExplosion.physicsBody?.collisionBitMask = PhysicsCategory.none
        freezeExplosion.physicsBody?.affectedByGravity = false
        freezeExplosion.physicsBody?.allowsRotation = false
        freezeExplosion.physicsBody?.isDynamic = false
        
        addChild(freezeExplosion)
        
        freezeExplosion.setScale(0.1)
        let scaleUp = SKAction.scale(to: 1.0, duration: 0.05)
        let fadeIn = SKAction.fadeIn(withDuration: 0.05)
        let wait = SKAction.wait(forDuration: 0.5)
        let fadeOut = SKAction.fadeOut(withDuration: 0.5)
        let group = SKAction.group([scaleUp, fadeIn])
        let remove = SKAction.removeFromParent()
        let explodeSequence = SKAction.sequence([group, wait, fadeOut, remove])
        freezeExplosion.run(explodeSequence)
    }
        
    func absorbShieldHit() {
        playerState.shieldHitsRemaining -= 1
        updateShieldAppearance()
        
        if playerState.shieldHitsRemaining <= 0 {
            removeSpectralShield()
        }
    }
    
//    func updateShieldAppearance() {
//        guard let shield = spectralShield else { return }
//        switch playerState.shieldHitsRemaining {
//        case playerState.shieldMaxHits:
//            shield.strokeColor = UIColor.green.withAlphaComponent(0.7)
//        case playerState.shieldMaxHits - 1:
//            shield.strokeColor = UIColor.orange.withAlphaComponent(0.7)
//        case 1:
//            shield.strokeColor = UIColor.red.withAlphaComponent(0.7)
//        default:
//            shield.strokeColor = UIColor.gray //Default or error color
//        }
//    }

    
    func fireHelpingHandProjectile() {
        guard let target = findNearestEnemy(within: 200.0) else {
            return
        }
        
        let projectile = SKSpriteNode(imageNamed: "sk_helping_hand")
        projectile.setScale(0.2)
        projectile.position = player.position
        projectile.name = "helpingHandProjectile"

        // MARK: Physics
        projectile.physicsBody = SKPhysicsBody(texture: projectile.texture!, size: projectile.size)
        projectile.physicsBody?.categoryBitMask = PhysicsCategory.projectile
        projectile.physicsBody?.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.boss | PhysicsCategory.border | PhysicsCategory.exploder
        projectile.physicsBody?.collisionBitMask = PhysicsCategory.none // Let's make helping hand not collide, just pass through
        projectile.physicsBody?.affectedByGravity = false
        projectile.physicsBody?.allowsRotation = false
        
        addChild(projectile)
        
        // Calculate direction vector towards the target
        let direction = CGVector(dx: target.position.x - player.position.x, dy: target.position.y - player.position.y).normalized
        projectile.zRotation = atan2(direction.dy, direction.dx)
        
        // Set up movement action (adjust `playerState.currentRange` as needed)
        let moveDistance: CGFloat = playerState.currentRange * 3.0
        let moveAction = SKAction.move(by: CGVector(dx: direction.dx * moveDistance, dy: direction.dy * moveDistance), duration: 2.0)
        
        // Placeholder for collision check (to be implemented later)
        let collisionAction = SKAction.run {
//            self.checkProjectileCollision(projectile)  Uncomment when collision is implemented
        }
        let collisionCheckSequence = SKAction.sequence([collisionAction, SKAction.wait(forDuration: 0.05)])
        let repeatCollisionCheck = SKAction.repeat(collisionCheckSequence, count: Int(2.0 / 0.05)) // Runs for duration of moveAction
        
        let combinedAction = SKAction.group([moveAction, repeatCollisionCheck])
        projectile.run(SKAction.sequence([combinedAction, SKAction.removeFromParent()]))
        
    }

    /// Finds the nearest enemy (zombie or wizard) within a specified radius.
    func findNearestEnemy(within radius: CGFloat) -> SKSpriteNode? {
        var nearestEnemy: SKSpriteNode?
        var shortestDistance = radius
        
        // Iterate through zombies to find the nearest one within the radius
        for zombie in enemyManager.enemies {
            let distance = hypot(zombie.position.x - player.position.x, zombie.position.y - player.position.y)
            if distance < shortestDistance {
                shortestDistance = distance
                nearestEnemy = zombie
            }
        }
        
        // Check if the wizard is within the radius and closer than any zombie
        if let wizard = scene?.childNode(withName: "wizard") as? ZPWizard {
            let distanceToWizard = hypot(wizard.position.x - player.position.x, wizard.position.y - player.position.y)
            if distanceToWizard < shortestDistance {
                shortestDistance = distanceToWizard
                nearestEnemy = wizard
            }
        }
        
        return nearestEnemy
    }
    
    func addSpectralShield() {
        // Avoid adding multiple shields
        if spectralShield != nil { return }
        guard let shieldContainer = shieldContainer else { return }
        
        // Remove existing shield
        shieldContainer.removeAllChildren()
        
        // Create the shield node
        let shield = SKShapeNode(circleOfRadius: 60)
        shield.alpha = 0.7
        shield.lineWidth = 2
        shield.position = CGPoint.zero
        shield.zPosition = 2 // On top of the player
        shield.name = "spectralShield"
        
        shield.physicsBody = SKPhysicsBody(circleOfRadius: 60)
        shield.physicsBody?.categoryBitMask = PhysicsCategory.shield
        shield.physicsBody?.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.boss | PhysicsCategory.exploder
        shield.physicsBody?.collisionBitMask = PhysicsCategory.none
        shield.physicsBody?.affectedByGravity = false
        shield.physicsBody?.allowsRotation = false
        shield.physicsBody?.isDynamic = false
        
        shieldContainer.addChild(shield)
        spectralShield = shield
        
        // Reset shield durability
        playerState.shieldHitsRemaining = playerState.shieldMaxHits
        updateShieldAppearance()
        
        // Add shield instance nodes
        addShieldInstances()
    }

    private func addShieldInstances() {
        guard let shield = spectralShield else { return }

        // Remove existing shield instance nodes
        shield.removeAllChildren()

        let shieldHits = playerState.shieldHitsRemaining
        let radius: CGFloat = 60.0 // Distance from the center of the shield
        let angleIncrement = (2 * CGFloat.pi) / CGFloat(shieldHits)

        for i in 0..<shieldHits {
            let angle = CGFloat(i) * angleIncrement
            let xPosition = radius * cos(angle)
            let yPosition = radius * sin(angle)

            let shieldInstance = SKSpriteNode(imageNamed: "sk_shield_instance")
            shieldInstance.setScale(0.3)
            shieldInstance.position = CGPoint(x: xPosition, y: yPosition)
            shieldInstance.zPosition = shield.zPosition + 1 // Ensure they render above the shield
            shieldInstance.name = "shieldInstance"
            
            // Ensure shield instance stays upright
            shieldInstance.zRotation = 0
            
            shield.addChild(shieldInstance)
        }

        // Animate the rotation
        animateShieldInstances(shield)
    }

    private func animateShieldInstances(_ shield: SKShapeNode) {
        let radius: CGFloat = 60.0 // Same radius as above
        let duration: TimeInterval = 2.0 // Time for a full rotation
        let shieldHits = playerState.shieldHitsRemaining
        let angleIncrement = (2 * CGFloat.pi) / CGFloat(shieldHits)

        // Animation block to update the position of each shield instance
        let rotateAction = SKAction.customAction(withDuration: duration) { _, elapsedTime in
            let currentAngle = (2 * CGFloat.pi) * (elapsedTime / CGFloat(duration))

            for (index, child) in shield.children.enumerated() {
                guard let shieldInstance = child as? SKSpriteNode else { continue }
                let angle = currentAngle + (CGFloat(index) * angleIncrement)
                let xPosition = radius * cos(angle)
                let yPosition = radius * sin(angle)

                shieldInstance.position = CGPoint(x: xPosition, y: yPosition)
                shieldInstance.zRotation = 0 // Keep upright
            }
        }

        let repeatRotation = SKAction.repeatForever(rotateAction)
        shield.run(repeatRotation, withKey: "rotateShieldInstances")
    }
    
    func updateShieldAppearance() {
        guard let shield = spectralShield else { return }
        
        // Update stroke color based on hits remaining
        switch playerState.shieldHitsRemaining {
        case playerState.shieldMaxHits:
            shield.strokeColor = UIColor.green.withAlphaComponent(0.7)
        case playerState.shieldMaxHits - 1:
            shield.strokeColor = UIColor.orange.withAlphaComponent(0.7)
        case 1:
            shield.strokeColor = UIColor.red.withAlphaComponent(0.7)
        default:
            shield.strokeColor = UIColor.gray // Default or error color
        }
        
        // Update shield instances to match remaining hits
        addShieldInstances()
    }
    
    func removeSpectralShield() {
        if let shield = spectralShield {
            shield.removeAllActions()
            shield.removeFromParent()
            spectralShield = nil
        }

        playerState.spectralShieldActive = false
        
        //Start cooldown timer to reactivate the shield after 'shieldCooldown'
        DispatchQueue.main.asyncAfter(deadline: .now() + playerState.shieldCooldown) { [weak self] in
            guard let self = self else { return }
            let ownsSpectralShield = self.skillManager.ownedSpecialSkills.contains { $0.type == .spectralShield }
            if ownsSpectralShield {
                self.playerState.activateSpectralShield()
            }
        }
    }
    
    func applyKnockback(to enemy: SKSpriteNode, strength: CGFloat, duration: TimeInterval) {
        // Calculate the direction vector from player to enemy
        let dx = enemy.position.x - player.position.x
        let dy = enemy.position.y - player.position.y
        let magnitude = sqrt(dx * dx + dy * dy)
        
        // Avoid division by zero
        guard magnitude != 0 else { return }
        
        // Normalize the direction vector
        let normalizedDx = dx / magnitude
        let normalizedDy = dy / magnitude
        
        // Determine the knockback vector based on strength
        let knockbackVector = CGVector(dx: normalizedDx * strength, dy: normalizedDy * strength)
        
        // Calculate the new position by adding the knockback vector
        var newPosition = CGPoint(x: enemy.position.x + knockbackVector.dx,
                                  y: enemy.position.y + knockbackVector.dy)
        
        // Clamp the new position within scene bounds to prevent enemies from moving off-screen
        newPosition.x = max(enemy.size.width / 2, min(newPosition.x, size.width - enemy.size.width / 2))
        newPosition.y = max(enemy.size.height / 2, min(newPosition.y, size.height - enemy.size.height / 2))
        
        // Create the move action
        let moveAction = SKAction.move(to: newPosition, duration: duration)
        moveAction.timingMode = .easeOut
        
        // Optionally, add a visual feedback (e.g., flash)
        let flashAction = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.5, duration: 0.05),
            SKAction.fadeAlpha(to: 1.0, duration: 0.05)
        ])
        
        // Run the actions on the enemy
        enemy.run(SKAction.sequence([flashAction, moveAction]), withKey: "knockback")
    }
    
    func performMightyKnockback() {
        print("KNOCBACK")
        // Radius of the knockback
        let knockbackRadius: CGFloat = 100.0
        let knockbackStrength: CGFloat = 200.0
        let knockbackDuration: TimeInterval = 0.3

        // Apply knockback to all enemies in range
        for enemy in enemyManager.enemies {
            let distance = player.position.distance(to: enemy.position)
            if distance <= knockbackRadius {
                applyKnockback(to: enemy, strength: knockbackStrength, duration: knockbackDuration)
            }
        }

        // Add visual effect
        let knockbackEmitter = SKEmitterNode(fileNamed: "SKKnockBack")
        knockbackEmitter?.position = player.position
        knockbackEmitter?.zPosition = player.zPosition - 1

        // Add the emitter to the scene
        addChild(knockbackEmitter!)

        // Remove emitter after its effect ends
        let removeEmitter = SKAction.sequence([
            SKAction.wait(forDuration: 0.5),
            SKAction.removeFromParent()
        ])
        knockbackEmitter!.run(removeEmitter)
    }
    
    func createKnockbackEmitter() -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = SKTexture(imageNamed: "spark") // Use an appropriate texture for your effect.
        emitter.particleColor = .red
        emitter.particleColorBlendFactor = 1.0
        emitter.particleLifetime = 0.5
        emitter.particleBirthRate = 200
        emitter.particleSpeed = 150
        emitter.particleSpeedRange = 50
        emitter.emissionAngleRange = CGFloat.pi * 2
        emitter.particleAlpha = 0.7
        emitter.particleAlphaRange = 0.2
        emitter.particleAlphaSpeed = -0.5
        emitter.particleScale = 0.2
        emitter.particleScaleRange = 0.1
        emitter.particleScaleSpeed = -0.2
        emitter.position = player.position
        emitter.zPosition = 5
        return emitter
    }
    
    func activateMightyKnockback() {
        guard playerState.mightyKnockbackActive else { return }
        playerState.mightyKnockbackActive = true

        let knockbackAction = SKAction.run { [weak self] in
            self?.performMightyKnockback()
        }
        let waitAction = SKAction.wait(forDuration: 7.0)
        let knockbackSequence = SKAction.sequence([knockbackAction, waitAction])
        let repeatKnockback = SKAction.repeatForever(knockbackSequence)
        
        run(repeatKnockback, withKey: "mightyKnockback")
    }

    func deactivateMightyKnockback() {
        playerState.mightyKnockbackActive = false
        removeAction(forKey: "mightyKnockback")
    }
    
    func applyContinuousDamage(currentTime: TimeInterval) {
        //Initialize lastDamageTime if it's the first call
        if lastDamageTime == 0.0 {
            lastDamageTime = currentTime
            return
        }
        
        //Check if enough time has passed to apply damage
        if currentTime - lastDamageTime >= damageInterval {
            //Create temporary array to iterate
            let enemiesToProcess = Array(damagingEnemies)
            
            for enemy in enemiesToProcess {
                guard !enemy.isDead, enemy.parent != nil else {
                    damagingEnemies.remove(enemy)
                    continue
                }
                
                if isPlayerStillInContact(with: enemy) {
                    applyDamageToPlayer(from: enemy)
                    //Can add visual feedback here
                } else {
                    resumeEnemyMovement(enemy)
                    damagingEnemies.remove(enemy)
                }
            }
            lastDamageTime = currentTime
        }
    }
    
    func applyBeamDamage() {
        //Identify beams that are no longer in the scene
        var beamsToRemove: [SKPhysicsBody] = []
        for beamBody in activeBeamContacts {
            if beamBody.node?.parent == nil {
                beamsToRemove.append(beamBody)
            }
        }
        //Remove beams that are no longer present
        for beamBody in beamsToRemove {
            activeBeamContacts.remove(beamBody)
        }
        if !activeBeamContacts.isEmpty {
            bossHitPlayer()
        }
    }
    
    func isPlayerStillInContact(with enemy: ZPZombie) -> Bool {
        //Can use either physics contact info or distance check
        let distance = player.position.distance(to: enemy.position)
        let contactRadius: CGFloat = (player.size.width + enemy.size.width) / 2
        
        return distance <= contactRadius
    }
    
    func updateXPBar() {
        xpBarNode.setXP(currentXP: upgradeShopManager.XPCount,
                        xpToNextLevel: upgradeShopManager.XPToNextLevel,
                        xpThreshold: upgradeShopManager.nextShopXPThreshold)
    }
    
    func handleEnemyDefeat(at lastHitZombiePosition: CGPoint) {
        spawnXPNode(at: lastHitZombiePosition)
        
        // MARK: Delete later, just for testing purposes
//        let spinnerOverlay = BossSpinnerOverlayNode(skillManager: skillManager, overlayManager: overlayManager, overlaySize: size)
//        overlayManager.enqueueOverlay(spinnerOverlay)
        
        score += 1
        pendingEnemies -= 1
        if pendingEnemies < 0 {
            pendingEnemies = 0
        }
        updateProgressLabel()
        
        //If pendingEnemies is zero and wave progression is not already ongoing
        if pendingEnemies == 0 {
            if waveCycle[currentWaveIndex].requiresFullClearance {
                //proceed to next wave immediately
                //cancel any scheduled wave progression
                waveProgressionWorkItem?.cancel()
                waveProgressionWorkItem = nil
                transitionToNextWave()
            } else if waveCycle[currentWaveIndex].allEnemiesSpawned {
                handleWaveProgression()
            }
        }
    }
    
    func checkXPCollection() {
        for (_, xpNode) in xpNodes.enumerated().reversed() {
            let distance = player.position.distance(to: xpNode.position)
            if distance < playerState.currentXPRadius {
                
                if let idx = self.xpNodes.firstIndex(where: { $0 === xpNode }) {
                    self.xpNodes.remove(at: idx)
                }
                xpNodesToRemove.append(xpNode)
                
                let moveAction = SKAction.move(to: player.position, duration: 0.1)
                let scaleAction = SKAction.scale(to: 0.0, duration: 0.1)
                let groupAction = SKAction.group([moveAction, scaleAction])
                                
                
                let removeAction = SKAction.run { [weak self, weak xpNode] in
                    guard let self = self, let xpNode = xpNode else { return }
                    
                    if let idx = self.xpNodesToRemove.firstIndex(where: { $0 === xpNode }) {
                        self.xpNodesToRemove.remove(at: idx)
                    }
                    
                    // Update player XP
                    self.playerState.currentXP += xpNode.xpAmount
                    self.upgradeShopManager.incrementXPCount()
                    self.updateXPBar()
                    
                    // Remove the XP node from the scene
                    xpNode.removeFromParent()

                }
                
                let sequence = SKAction.sequence([groupAction, removeAction])
                
                xpNode.run(sequence)
            }
        }
    }
    
    func spawnXPNode(at position: CGPoint) {
        let timeUntilDespawn: TimeInterval = 25
        
        let xpValue = 1
        let xpNode = XPNode(xpAmount: xpValue)
        xpNode.position = position
        xpNode.zPosition = player.zPosition - 1
        
        xpNode.alpha = 0.0
        xpNode.setScale(0.0)
        
        addChild(xpNode)
        xpNodes.append(xpNode)
        
        // Spawn animation
        let scaleUp = SKAction.scale(to: 1.1, duration: 0.2)
        let scaleDown = SKAction.scale(to: 1.0, duration: 0.1)
        let fadeIn = SKAction.fadeIn(withDuration: 0.3)
        let spawnGroup = SKAction.group([scaleUp, fadeIn])
        let spawnSequence = SKAction.sequence([spawnGroup, scaleDown])
        
        xpNode.run(spawnSequence)
        
        // Despawn animation
        let despawnDelay = SKAction.wait(forDuration: timeUntilDespawn)
        let fadeOut = SKAction.fadeOut(withDuration: 0.2)
        let shrink = SKAction.scale(to: 0.0, duration: 0.2)
        let group = SKAction.group([fadeOut, shrink])
        let removeFromScene = SKAction.removeFromParent()
        let removeFromArray = SKAction.run { [weak self, weak xpNode] in
            guard let self = self, let node = xpNode else { return }
            if let index = self.xpNodes.firstIndex(where: { $0 === node }) {
                self.xpNodes.remove(at: index)
            }
        }
        
        let sequence = SKAction.sequence([despawnDelay, group, removeFromScene, removeFromArray])
        xpNode.run(sequence)
    }
    
    func spawnRandomXPNode() {
        guard let player = player else { return }

        let spawnBuffer: CGFloat = 80.0
        let spawnRadius: CGFloat = size.height / 2.0
        let xpSize = CGSize(width: 20, height: 20) // approximate XP size
        
        var attempts = 0
        let maxAttempts = 100
        var validPosition: CGPoint?
        
        while attempts < maxAttempts {
            let angle = CGFloat.random(in: 0...2 * .pi)
            let distance = CGFloat.random(in: spawnBuffer...spawnRadius)
            
            let offsetX = distance * cos(angle)
            let offsetY = distance * sin(angle)
            var randomPosition = CGPoint(x: player.position.x + offsetX, y: player.position.y + offsetY)
            randomPosition.y = min(max(randomPosition.y, mapManager.bottomBound + spawnBuffer), mapManager.topBound - spawnBuffer)
            
            // Check if position is clear of obstacles
            if mapManager.positionIsClear(position: randomPosition, entitySize: xpSize) {
                validPosition = randomPosition
                break
            }
            
            attempts += 1
        }
        // If no valid position found, do not spawn XP
        guard let spawnPosition = validPosition else { return }
        
        spawnXPNode(at: spawnPosition)
    }
    
    func startXPSpawnTimer() {
        guard xpSpawnTimer == nil else { return }
        
        xpSpawnTimer = Timer.scheduledTimer(withTimeInterval: xpSpawnInterval, repeats: true) { [weak self] _ in
            self?.spawnRandomXPNode()
        }
    }
    
    func stopXPSpawnTimer() {
        xpSpawnTimer?.invalidate()
        xpSpawnTimer = nil
    }
    
    func bossHitPlayer() {
        flashPlayer()
        playerLives -= 1
    }
    
//    private func showEnemyIntroductionMessage(_ message: String) {
//        guard let cameraNode = self.camera else { return }
//        let enemyMessageLabel = SKLabelNode(text: message)
//        enemyMessageLabel.fontName = "Arial"
//        enemyMessageLabel.fontSize = 40
//        enemyMessageLabel.fontColor = .red
//        enemyMessageLabel.position = CGPoint(x: 0, y: size.height * 0.25)
//        enemyMessageLabel.zPosition = 5
//        cameraNode.addChild(enemyMessageLabel)
//        
//        let fadeOut = SKAction.sequence([
//            SKAction.wait(forDuration: 5.0),
//            SKAction.fadeOut(withDuration: 0.5),
//            SKAction.run { enemyMessageLabel.removeFromParent() }
//        ])
//        enemyMessageLabel.run(fadeOut)
//    }
    
    func showEnemyIntroductionMessage(forWaveNumber waveNumber: Int) {
        // Map the wave number to the appropriate banner
        if let bannerName = newEnemyBannerMapping[waveNumber] {
            showBannerNode(imageName: bannerName, duration: 5.0)
        }
    }

    
    func showGameOverScreen() {
        gameOver = true
        guard let cameraNode = self.camera else { return }
        
        // 1. Create and fade in the red opaque rectangle
        let redOverlay = SKSpriteNode(color: UIColor(hex: "#200000") ?? .red, size: self.size)
        redOverlay.position = CGPoint(x: 0, y: 0)
        redOverlay.zPosition = 10 // Ensure it's above other nodes
        redOverlay.alpha = 0.0
        redOverlay.name = "redOverlay"
        cameraNode.addChild(redOverlay)
        
        let fadeInRed = SKAction.fadeAlpha(to: 0.7, duration: 0.5) // Adjust alpha as needed
        redOverlay.run(fadeInRed)
        
        // 2. Create and fade in the "sk_game_over" image
        let gameOverImage = SKSpriteNode(imageNamed: "sk_game_over")
        gameOverImage.position = CGPoint(x: 0, y: 50) // Adjust position as needed
        gameOverImage.zPosition = 11 // Above redOverlay
        gameOverImage.alpha = 0.0
        gameOverImage.name = "gameOverImage"
        cameraNode.addChild(gameOverImage)
        
        let fadeInGameOverImage = SKAction.fadeAlpha(to: 1.0, duration: 1.0)
        gameOverImage.run(fadeInGameOverImage)
        
        // 3. After 4 seconds, show the game over flow
        let wait = SKAction.wait(forDuration: 4.0)
        let showGameOverFlow = SKAction.run { [weak self] in
            self?.presentGameOverFlow()
        }
        let sequence = SKAction.sequence([wait, showGameOverFlow])
        cameraNode.run(sequence)
    }
    
    func presentGameOverFlow() {
        guard let cameraNode = self.camera else { return }
        
        // 4. Create the game over node with buttons
        let gameOverNode = SKShapeNode(rect: CGRect(x: -size.width * 0.4, y: -size.height * 0.2, width: size.width * 0.8, height: size.height * 0.4), cornerRadius: 20)
        gameOverNode.fillColor = .black.withAlphaComponent(0.8)
        gameOverNode.name = "gameOverScreen"
        gameOverNode.zPosition = 12 // Above everything else
        gameOverNode.alpha = 0.0 // Start invisible
        cameraNode.addChild(gameOverNode)
        
        // Fade in the game over node
        let fadeInGameOverNode = SKAction.fadeAlpha(to: 1.0, duration: 1.0)
        gameOverNode.run(fadeInGameOverNode)
        
        // Add "Game Over" label with a slight delay
        let gameOverLabel = SKLabelNode(text: "Game Over")
        gameOverLabel.fontName = "Arial"
        gameOverLabel.fontSize = 40
        gameOverLabel.fontColor = .white
        gameOverLabel.position = CGPoint(x: 0, y: gameOverNode.frame.height * 0.3)
        gameOverLabel.zPosition = 13
        gameOverLabel.alpha = 0.0
        gameOverNode.addChild(gameOverLabel)
        
        let fadeInLabel = SKAction.fadeAlpha(to: 1.0, duration: 1.0)
        let moveUp = SKAction.moveBy(x: 0, y: 10, duration: 1.0)
        let labelAction = SKAction.group([fadeInLabel, moveUp])
        gameOverLabel.run(labelAction)
        
        // Add Score label
        let scoreLabel = SKLabelNode(text: "Score: \(score)")
        scoreLabel.fontName = "Arial"
        scoreLabel.fontSize = 30
        scoreLabel.fontColor = .white
        scoreLabel.position = CGPoint(x: 0, y: gameOverNode.frame.height * 0.1)
        scoreLabel.zPosition = 13
        scoreLabel.alpha = 0.0
        gameOverNode.addChild(scoreLabel)
        
        let fadeInScoreLabel = SKAction.fadeAlpha(to: 1.0, duration: 1.0)
        scoreLabel.run(fadeInScoreLabel)
        
        // Add Retry button with animation
        let retryButton = createButton(withText: "Retry", atPosition: CGPoint(x: 0, y: -gameOverNode.frame.height * 0.1))
        retryButton.name = "retryButton"
        retryButton.alpha = 0.0
        gameOverNode.addChild(retryButton)
        
        let fadeInRetry = SKAction.fadeAlpha(to: 1.0, duration: 1.0)
        let scaleUpRetry = SKAction.scale(to: 1.2, duration: 0.5)
        let scaleDownRetry = SKAction.scale(to: 1.0, duration: 0.5)
        let pulseRetry = SKAction.sequence([scaleUpRetry, scaleDownRetry])
        let retryAction = SKAction.group([fadeInRetry, pulseRetry])
        retryButton.run(retryAction)
    }
    
    func createButton(withText text: String, atPosition position: CGPoint) -> SKLabelNode {
        let button = SKLabelNode(text: text)
        button.fontSize = 25
        button.fontColor = .white
        button.position = position
        return button
    }
    
    func restartGame() {
        if let cameraNode = self.camera, let gameOverScreen = cameraNode.childNode(withName: "gameOverScreen") {
            gameOverScreen.removeFromParent()
        }
        player.position = centerPosition
        joystick.endTouch()
        shootJoystick.endTouch()
        waveCounter = 0
        currentWaveIndex = 0
        zombieHealth = 3
        zombieSpeed = 0.3
        wizardHealth = 15
        enemiesToDefeat = 3
        maxRegularZombies = 3
        maxChargerZombies = 0
        maxExploderZombies = 0
        miniWaveInterval = 3.0
        isBossStage = false
        arenaBounds = nil
        gracePeriod = 10.0
        pendingEnemies = 0
        enemiesToSpawn = 0
        
        playerState.currentXP = 0
        playerState.resetToBaseStats()
        
        if let existingWizard = wizardBoss {
            existingWizard.removeFromParent()
            wizardBoss = nil
        }
        setUpGame()
    }
    
    func updateUpgradeStatsLabel() {
        upgradeStatsLabel.text = "Dmg: \(playerState.currentDamage) | Range: \(playerState.currentRange) | AtkSpeed: \(playerState.currentAttackSpeed)"
    }
    
    //Function used to handle removing zombies from tracking structure (in exploder class)
    func removeZombieFromTracking(_ zombie: ZPExploderZombieNode) {
        if let index = enemyManager.enemies.firstIndex(where: { $0 === zombie }) {
            enemyManager.enemies.remove(at: index)
        }
    }
    
    func stopEnemyMovement(_ enemy: ZPZombie) {
        enemy.removeAllActions()
        enemy.isAttacking = true
    }
    
    func resumeEnemyMovement(_ enemy: ZPZombie) {
        enemy.isAttacking = false
        enemy.moveTowards(playerPosition: player.position)
    }
    
}



extension ZPGameScene: SKPhysicsContactDelegate {
    
    func didBegin(_ contact: SKPhysicsContact) {
        let bodyA = contact.bodyA
        let bodyB = contact.bodyB

        let categoryA = bodyA.categoryBitMask
        let categoryB = bodyB.categoryBitMask

        // Sort so we always have lower category first for easier logic
        let firstBody: SKPhysicsBody
        let secondBody: SKPhysicsBody

        if categoryA < categoryB {
           firstBody = bodyA
           secondBody = bodyB
        } else {
           firstBody = bodyB
           secondBody = bodyA
        }
        
        if (firstBody.categoryBitMask == PhysicsCategory.player && secondBody.categoryBitMask == PhysicsCategory.border) {
//            print("🔴 Player collided with Border")
        }

        // Player & Enemy collision
        if (firstBody.categoryBitMask == PhysicsCategory.player && secondBody.categoryBitMask == PhysicsCategory.enemy) {
            if let enemyNode = secondBody.node as? ZPZombie {
                if enemyNode.lastHitPlayerTime + enemyNode.hitPlayerCooldown < currentGameTime {
                    startDamagingPlayer(with: enemyNode, currentTime: currentGameTime)
                    enemyNode.lastHitPlayerTime = currentGameTime
                }
            }
        }

        // Projectile & Enemy/Boss collision
        if ((firstBody.categoryBitMask == PhysicsCategory.enemy || firstBody.categoryBitMask == PhysicsCategory.boss || firstBody.categoryBitMask == PhysicsCategory.exploder) && secondBody.categoryBitMask == PhysicsCategory.projectile) {
            if let projectileNode = secondBody.node as? SKSpriteNode {
                if let enemyNode = firstBody.node as? ZPZombie {
                    if shouldDamageEnemy(projectile: projectileNode, enemy: enemyNode) {
                        handleProjectileCollision(with: enemyNode)
                    }
                } else if let bossNode = firstBody.node as? ZPWizard {
                    if shouldDamageEnemy(projectile: projectileNode, enemy: bossNode) {
                        handleProjectileCollision(with: bossNode)
                    }
                }
                if !playerState.projectilesPierce {
                    projectileNode.removeFromParent()
                }
            }
        }
        
        //Player & Beam Collision
        if (firstBody.categoryBitMask == PhysicsCategory.bossBeam && secondBody.categoryBitMask == PhysicsCategory.player) || (firstBody.categoryBitMask == PhysicsCategory.player && secondBody.categoryBitMask == PhysicsCategory.bossBeam) {
            if let beamNode = firstBody.categoryBitMask == PhysicsCategory.bossBeam ? firstBody.node : secondBody.node,
               let beamBody = beamNode.physicsBody {
                activeBeamContacts.insert(beamBody)
            }
            
        }
        
        // remove projectile if it hits border
        if ((firstBody.categoryBitMask == PhysicsCategory.border) && secondBody.categoryBitMask == PhysicsCategory.projectile) {
            if let projectileNode = secondBody.node as? SKSpriteNode {
                if !playerState.projectilesPierce {
                    projectileNode.removeFromParent()
                }
            }
        }
        
        // Freeze Explosion & Enemy/Boss collision
        if ((firstBody.categoryBitMask == PhysicsCategory.enemy || firstBody.categoryBitMask == PhysicsCategory.boss || firstBody.categoryBitMask == PhysicsCategory.exploder) && secondBody.categoryBitMask == PhysicsCategory.freeze) {
            let currentTime = CACurrentMediaTime()
            if let enemyNode = firstBody.node as? ZPZombie {
                enemyNode.freeze(currentTime: currentTime, duration: playerState.freezeDuration)
            } else if let bossNode = firstBody.node as? ZPWizard {
                bossNode.freeze(currentTime: currentTime, duration: playerState.freezeDuration)
            }
        }

        // Blade & Enemy/Boss collision
        if ((firstBody.categoryBitMask == PhysicsCategory.enemy || firstBody.categoryBitMask == PhysicsCategory.boss || firstBody.categoryBitMask == PhysicsCategory.exploder) && secondBody.categoryBitMask == PhysicsCategory.blade) {
            if let enemyNode = firstBody.node as? ZPZombie {
                handleBladeCollision(with: enemyNode)
            } else if let bossNode = firstBody.node as? ZPWizard {
                handleBladeCollision(with: bossNode)
            }
        }
        
        // Barrier & Enemy/Boss collision
        if ((firstBody.categoryBitMask == PhysicsCategory.enemy || firstBody.categoryBitMask == PhysicsCategory.boss || firstBody.categoryBitMask == PhysicsCategory.exploder) && secondBody.categoryBitMask == PhysicsCategory.protectiveBarrier) {
            if let enemyNode = firstBody.node as? ZPZombie {
                handleBarrierCollision(withEnemy: enemyNode)
            } else if let bossNode = firstBody.node as? ZPWizard {
                handleBarrierCollision(withBoss: bossNode)
            }
        }
        
        // Shield & Enemy/Boss collision
        if ((firstBody.categoryBitMask == PhysicsCategory.enemy || firstBody.categoryBitMask == PhysicsCategory.boss || firstBody.categoryBitMask == PhysicsCategory.exploder) && secondBody.categoryBitMask == PhysicsCategory.shield) {
            if let enemyNode = firstBody.node as? ZPZombie {
                handleShieldCollision(withEnemy: enemyNode)
            } else if let bossNode = firstBody.node as? ZPWizard {
                handleShieldCollision(withBoss: bossNode)
            }
        }

    }
    
    func didEnd(_ contact: SKPhysicsContact) {
        let bodyA = contact.bodyA
        let bodyB = contact.bodyB

        let categoryA = bodyA.categoryBitMask
        let categoryB = bodyB.categoryBitMask

        let firstBody: SKPhysicsBody
        let secondBody: SKPhysicsBody

        if categoryA < categoryB {
           firstBody = bodyA
           secondBody = bodyB
        } else {
           firstBody = bodyB
           secondBody = bodyA
        }

        if ((firstBody.categoryBitMask == PhysicsCategory.enemy || firstBody.categoryBitMask == PhysicsCategory.boss) &&
            secondBody.categoryBitMask == PhysicsCategory.protectiveBarrier) {
            
            if let enemyNode = firstBody.node as? ZPZombie {
                enemyNode.isSlowedByBarrier = false
                enemyNode.movementSpeed = enemyNode.baseSpeed
                enemyNode.color = enemyNode.baseColor
                enemyNode.colorBlendFactor = 1.0
            } else if let bossNode = firstBody.node as? ZPWizard {
                bossNode.isSlowedByBarrier = false
                bossNode.movementSpeed = bossNode.baseSpeed
                bossNode.color = bossNode.baseColor
                bossNode.colorBlendFactor = 1.0
            }
        }
        
        //Player and beam collision end
        if (firstBody.categoryBitMask == PhysicsCategory.bossBeam && secondBody.categoryBitMask == PhysicsCategory.player) || (firstBody.categoryBitMask == PhysicsCategory.player && secondBody.categoryBitMask == PhysicsCategory.bossBeam) {
            if let beamNode = firstBody.categoryBitMask == PhysicsCategory.bossBeam ? firstBody.node : secondBody.node,
               let beamBody = beamNode.physicsBody {
                activeBeamContacts.remove(beamBody)
            }
        }
    }
    
    // MARK: Collision Methods
    
    /// Handles collisions between the Projectile and a ZPZombie (enemy).
    func handleProjectileCollision(with enemy: ZPZombie) {
        applyDamageToEnemy(enemy, damage: playerState.currentDamage)
    }
    
    /// Handles collisions between the Projectile and the ZPWizard (boss).
    func handleProjectileCollision(with boss: ZPWizard) {
        applyDamageToBoss(boss, damage: playerState.currentDamage)
    }
    
    /// Handles collisions between the Blade and a ZPZombie (enemy).
    func handleBladeCollision(with enemy: ZPZombie) {
        let currentTime = CACurrentMediaTime()
        
        if currentTime - enemy.lastSpinningBladeDamageTime > playerState.spinningBladesDamageCooldown {
            enemy.lastSpinningBladeDamageTime = currentTime
            applyDamageToEnemy(enemy, damage: playerState.spinningBladesDamage)
        }
    }
    
    /// Handles collisions between the Blade and the ZPWizard (boss).
    func handleBladeCollision(with boss: ZPWizard) {
        let currentTime = CACurrentMediaTime()
        
        if currentTime - boss.lastSpinningBladeDamageTime > playerState.spinningBladesDamageCooldown {
            boss.lastSpinningBladeDamageTime = currentTime
            applyDamageToBoss(boss, damage: playerState.spinningBladesDamage)
        }
    }
    
    /// Handles collision between protective barrier and an enemy.
    func handleBarrierCollision(withEnemy enemy: ZPZombie) {
        let currentTime = CACurrentMediaTime()
        let damageCooldown: TimeInterval = max(0.3, 1.0 - playerState.barrierPulseFrequency)
        
        if currentTime - enemy.lastBarrierDamageTime > damageCooldown {
            enemy.lastBarrierDamageTime = currentTime
            applyDamageToEnemy(enemy, damage: playerState.currentDamage * playerState.barrierDamageFactor)
        }
        
        if !enemy.isSlowedByBarrier {
            enemy.isSlowedByBarrier = true
            enemy.movementSpeed = max(enemy.movementSpeed - playerState.barrierSlowAmount, 0.05)
        }
    }
    
    /// Handles collision between protective barrier and the boss.
    func handleBarrierCollision(withBoss boss: ZPWizard) {
        let currentTime = CACurrentMediaTime()
        let damageCooldown: TimeInterval = max(0.3, 1.0 - playerState.barrierPulseFrequency)
        
        if currentTime - boss.lastBarrierDamageTime > damageCooldown {
            boss.lastBarrierDamageTime = currentTime
            applyDamageToBoss(boss, damage: playerState.currentDamage * playerState.barrierDamageFactor)
        }
        
        if !boss.isSlowedByBarrier {
            boss.isSlowedByBarrier = true
            boss.movementSpeed = max(boss.movementSpeed - playerState.barrierSlowAmount, 0.05)
        }
    }
    
    /// Handles collision between the shield and a regular enemy
    func handleShieldCollision(withEnemy enemy: ZPZombie) {
        let currentTime = CACurrentMediaTime()
        let shieldHitCooldown: TimeInterval = 1.0
        
        if currentTime - enemy.lastShieldHitTime > shieldHitCooldown {
            enemy.lastShieldHitTime = currentTime
            absorbShieldHit()
            applyKnockback(to: enemy, strength: 50, duration: 0.3)
        }
    }

    /// Handles collision between the shield and the boss
    func handleShieldCollision(withBoss boss: ZPWizard) {
        absorbShieldHit()
        applyDamageToBoss(boss, damage: boss.health * playerState.spectralShieldDamageFactor)
    }
    
    
    // MARK: Helpers for collisions
    func startDamagingPlayer(with enemy: ZPZombie, currentTime: TimeInterval) {
        damagingEnemies.insert(enemy)
        stopEnemyMovement(enemy)
        applyDamageToPlayer(from: enemy)
        lastDamageTime = currentTime
    }
    
    func startDamagingPlayerWithBeam(withBeam beamNode: SKNode) {
        //Add beam's physics body to activeBeamContacts
        if let beamBody = beamNode.physicsBody {
            activeBeamContacts.insert(beamBody)
        }
        
        //Start applying damage every 0.5 seconds
        let damageAction = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.run { [weak self] in
                    self?.bossHitPlayer()
                },
                SKAction.wait(forDuration: 0.5)
            ])
        )
        beamNode.run(damageAction, withKey: "damagePlayerWithBeam")
    }
    
    func stopDamagingPlayerWithBeam(withBeam beamNode: SKNode) {
        //Remove beam's physics body from activeBeamContacts
        if let beamBody = beamNode.physicsBody {
            activeBeamContacts.remove(beamBody)
        }
        //Stop the damage action
        beamNode.removeAction(forKey: "damagePlayerWithBeam")
    }
    
    // Used to checking if piercing arrow should keep damaging same enemy or not
    func shouldDamageEnemy(projectile: SKSpriteNode, enemy: SKNode) -> Bool {
        guard let damagedEnemies = projectile.userData?.object(forKey: "damagedEnemies") as? NSMutableSet else {
            // Create a new set if it doesn't exist
            let newSet = NSMutableSet()
            projectile.userData?.setValue(newSet, forKey: "damagedEnemies")
            newSet.add(enemy)
            return true
        }
        
        if damagedEnemies.contains(enemy) {
            return false // Already damaged this enemy
        } else {
            damagedEnemies.add(enemy)
            return true // Enemy not yet damaged by this projectile
        }
    }
    
    func applyDamageToPlayer(from enemy: ZPZombie) {
        flashPlayer()
        playerLives -= 1
        updateProgressLabel()
        
        if playerLives <= 0 {
            showGameOverScreen()
        }
    }
    
    func applyDamageToBoss(_ boss: ZPWizard, damage: Double) {
        boss.takeDamage(amount: damage)
        if boss.health <= 0 {
            handleBossDefeat()
        }
    }
    
    func applyDamageToEnemy(_ enemy: ZPZombie, damage: Double) {
        enemy.takeDamage(amount: damage)
    }

}

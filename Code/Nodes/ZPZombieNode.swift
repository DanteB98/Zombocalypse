//
//  ZPZombieNode.swift
//  Zombocalypse
//
//
//

import SpriteKit

class ZPZombie: SKSpriteNode {
    var lastSpinningBladeDamageTime: TimeInterval = 0
    var lastBarrierDamageTime: TimeInterval = 0
    var isFrozen: Bool = false
    var freezeEndTime: TimeInterval = 0
    
    var health: Double {
        didSet{
            healthLabel.text = "Enemy | HP:\(health)"
        }
    }
    var isDead: Bool {
        return health <= 0
    }
    
    private let healthLabel: SKLabelNode
    
    
    init(health: Double) {
        self.health = health
        self.healthLabel = SKLabelNode(text: "Enemy | HP: \(health)")
        let size = CGSize(width: 25, height: 25)
        super.init(texture: nil, color: .red, size: size)
        healthLabel.fontSize = 20
        healthLabel.fontColor = .black
        healthLabel.position = CGPoint(x: 0, y: size.height / 2 + 10)
        addChild(healthLabel)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func moveTowards(player: SKSpriteNode, speed: CGFloat) {
        if isFrozen {
            //Do not move if frozen
            return
        }
        let direction = CGVector(dx: player.position.x - self.position.x, dy: player.position.y - self.position.y)
        let length = hypot(direction.dx, direction.dy)
        
        if length > 0 { // Check if the enemy is not at the player's position
            let normalizedDirection = CGVector(dx: direction.dx / length, dy: direction.dy / length)
            self.position = CGPoint(x: self.position.x + normalizedDirection.dx * speed, y: self.position.y + normalizedDirection.dy * speed)
        }
    }
    
    func takeDamage(amount: Double) {
        health -= amount
        if isDead {
            removeFromParent()
        }
    }
}

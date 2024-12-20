//
//  SLPlayerState.swift
//  Zombocalypse
//
//  Created by Sam Richard on 12/5/24.
//

import Foundation


/// This allows us to use SLGameScene as our "delegate" (sort of like a parent)
/// We can call only these 5 methods that we will implement in our delegate
protocol SLPlayerStateDelegate: AnyObject {
    // Regular Skills
    func playerStateDidAddSpinningBlades(_ state: SLPlayerState)
    func playerStateDidUpgradeBarrier(_ state: SLPlayerState)
    func playerStateDidUpgradeHealth(_ state: SLPlayerState, restorePercentage: Double) /// example of something condtional to pass to the GameScene
    func playerStateDidUpgradeMagnet(_ state: SLPlayerState)
    func playerStateDidUpgradeFreeze(_ state: SLPlayerState)
    
    // Special Skills
    func playerStateDidActivateHelpingHand(_ state: SLPlayerState)
    func playerStateDidDeactivateHelpingHand() /// to disable UI effects
    func playerStateDidActivateReinforcedArrow(_ state: SLPlayerState)
    func playerStateDidActivateSpectralShield(_ state: SLPlayerState)
    func playerStateDidDeactivateSpectralShield() /// to disable UI effects
    func playerStateDidActivateMightyKnockback(_ state: SLPlayerState)
    func playerStateDidDeactivateMightyKnockback()
    func playerStateDidActivateBonusHealth(_ state: SLPlayerState, restorePercentage: Double)
}


/// We'll need to make an instance of PlayerState in our SLGameScene to keep track of these values that are relevant to the player and the Skill Manager
/// Then, we will set SLGameScene as the delegate
///    [put this with the rest of the variables at the top of SLGameScene] var playerState = PlayerState()
///    [(probably put this in didMove()] playerState.delegate = self
class SLPlayerState {
    weak var delegate: SLPlayerStateDelegate?
    
    // Default values
    var baseDamage: Double = 1
    var baseAttackSpeed: Double = 1.0
    var baseMovementSpeed: Double = 100.0
    var baseRange: Double = 200.0
    var baseMaxHealth: Double = 5.0
    var baseXPRadius: Double = 40.0

    // Derived stats after skill application:
    var currentDamage: Double = 0
    var currentAttackSpeed: Double = 0
    var currentMovementSpeed: Double = 0
    var currentRange: Double = 0
    var currentMaxHealth: Double = 0
    var currentXPRadius: Double = 0
    
    let projectileSpeed: Double = 250.0
    
    // XP
    var currentXP: Int = 0
    
    // Spinning blades properties
    var spinningBladesCount: Int = 0
    var spinningBladesDamage: Double = 0.0
    var spinningBladesSpeed: Double = 0.0
    let spinningBladesDamageCooldown: TimeInterval = 1.0
    
    // Protective Barrier
    var barrierScale: Double = 0.0
    var barrierDamageFactor: Double = 0.0
    var barrierPulseFrequency: Double = 0.0
    var barrierSlowAmount: Double = 0.0

    // Freeze Grenade
    var freezeGrenadeActive: Bool = false
    let freezeGrenadeBaseCooldown: Double = 5.0
    var freezeGrenadeCooldownReduction: Double = 0.0
    var freezeDuration: Double = 0.0
    var freezeRadius: Double = 0.0
    
    // Special Skills On/Off
    var hasHelpingHand: Bool = false          // If true, extra projectile logic in scene
    var projectilesPierce: Bool = false       // If true, Reinforced Arrow effect
    var spectralShieldActive: Bool = false    // If true, a shield should appear around player
    var mightyKnockbackActive: Bool = false   // If true, every X seconds we push enemies away
    
    let spectralShieldDamageFactor: Double = 0.5
    let spectralShieldBossDamageFactor: Double = 0.1
    let shieldMaxHits: Int = 3
    let shieldCooldown: TimeInterval = 15.0
    var shieldHitsRemaining: Int = 3

    // This is called every time a new skill is added.
    // It is a refresh to make sure the increments don't stack
    func resetToBaseStats() {
        print("RESETTING PLAYER STATE")
        
        // Reset Base Stats
        currentDamage = baseDamage
        currentAttackSpeed = baseAttackSpeed
        currentMovementSpeed = baseMovementSpeed
        currentRange = baseRange
        currentMaxHealth = baseMaxHealth
        currentXPRadius = baseXPRadius
        
        // Reset Regular Skill Properties
        spinningBladesCount = 0
        spinningBladesDamage = 0
        spinningBladesSpeed = 0.0
        
        barrierScale = 0.0
        barrierDamageFactor = 0
        barrierPulseFrequency = 0.0
        barrierSlowAmount = 0.0

        freezeGrenadeActive = false
        freezeGrenadeCooldownReduction = 0.0
        freezeDuration = 0.0
        freezeRadius = 0.0
        
        // Reset Special Skill Flags
        hasHelpingHand = false
        projectilesPierce = false
        spectralShieldActive = false
        mightyKnockbackActive = false
        
        delegate?.playerStateDidDeactivateHelpingHand()
        delegate?.playerStateDidDeactivateSpectralShield()
        delegate?.playerStateDidDeactivateMightyKnockback()

        shieldHitsRemaining = 3
    }
    
    
    // MARK: Regular Skills
    func addSpinningBlades(count: Int, damage: Double, speed: Double) {
        spinningBladesCount += count
        spinningBladesDamage += damage
        spinningBladesSpeed += speed

        // Calls to logic in GameScene relating to this skill
        delegate?.playerStateDidAddSpinningBlades(self)
    }
    
    func upgradeBarrier(sizeIncrement: Double, damageIncrement: Double, pulseFrequencyIncrement: Double, slowAmountIncrement: Double) {
        barrierScale += sizeIncrement
        barrierDamageFactor += damageIncrement
        barrierPulseFrequency += pulseFrequencyIncrement
        barrierSlowAmount += slowAmountIncrement
        
        // Calls to logic in GameScene relating to this skill
        delegate?.playerStateDidUpgradeBarrier(self)
    }

    func upgradeHealth(by amount: Double, restorePercentage: Double) {
        currentMaxHealth += amount
        
        // Calls to logic in GameScene relating to this skill
        delegate?.playerStateDidUpgradeHealth(self, restorePercentage: restorePercentage)
    }

    func upgradeMagnet(by amount: Double) {
        currentXPRadius += amount
        
        // Calls to logic in GameScene relating to this skill
        delegate?.playerStateDidUpgradeMagnet(self)
    }

    func upgradeFreeze(cooldownReduction: Double, durationIncrement: Double, radiusIncrement: Double) {
        freezeGrenadeCooldownReduction += cooldownReduction
        freezeDuration += durationIncrement
        freezeRadius += radiusIncrement
        freezeGrenadeActive = true
        
        // Calls to logic in GameScene relating to this skill
        delegate?.playerStateDidUpgradeFreeze(self)
    }
    
    // MARK: Special Skills
    func activateHelpingHand() {
        hasHelpingHand = true
        
        // Calls to logic in GameScene relating to this skill
        delegate?.playerStateDidActivateHelpingHand(self)
    }

    func activateReinforcedArrow() {
        projectilesPierce = true
        
        // Calls to logic in GameScene relating to this skill
        delegate?.playerStateDidActivateReinforcedArrow(self)
    }

    func activateSpectralShield() {
        spectralShieldActive = true
        
        // Calls to logic in GameScene relating to this skill
        delegate?.playerStateDidActivateSpectralShield(self)
    }

    func activateMightyKnockback() {
        mightyKnockbackActive = true
        
        // Calls to logic in GameScene relating to this skill
        delegate?.playerStateDidActivateMightyKnockback(self)
    }
    
    // MARK: Bonus "Skills"
    func activateBonusHealth() {
        // Calls to logic in GameScene relating to this skill
        delegate?.playerStateDidActivateBonusHealth(self, restorePercentage: 0.5)
    }
}

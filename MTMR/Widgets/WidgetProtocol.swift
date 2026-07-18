//
//  WidgetProtocol.swift
//  MTMR
//
//  Created by Anton Palgunov on 20/10/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

@MainActor
protocol Widget {
    static var name: String { get }
    static var identifier: String { get }
}

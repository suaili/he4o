//
//  NodeView.h
//  SMG_NothingIsAll
//
//  Created by jia on 2019/6/11.
//  Copyright © 2019年 XiaoGang. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol NodeViewDelegate <NSObject>

-(UIView*) nodeView_GetCustomSubView:(id)nodeData;
-(NSString*) nodeView_GetDesc:(id)nodeData;

@end

/**
 *  MARK:--------------------节点view--------------------
 */
@interface NodeView : UIView

@property (weak, nonatomic) id<NodeViewDelegate> delegate;
-(void) setDataWithNodeData:(id)nodeData;

@end

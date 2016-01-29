//
//  SSProxy.m
//  Test
//
//  Created by Jason Hsu on 13-9-7.
//  Copyright (c) 2013年 Jason Hsu. All rights reserved.
//

#import "ShadowsocksClient.h"
#include "encrypt.h"
#include "socks5.h"
#include <arpa/inet.h>
#import <UIKit/UIKit.h>

#define ADDR_STR_LEN 512

@interface SSPipeline : NSObject
{
@public
    struct encryption_ctx sendEncryptionContext;
    struct encryption_ctx recvEncryptionContext;
}


@property (nonatomic, strong) GCDAsyncSocket *localSocket;
@property (nonatomic, strong) GCDAsyncSocket *remoteSocket;
@property (nonatomic, assign) int stage;
@property (nonatomic, strong) NSData *addrData;

- (void)disconnect;

@end

@implementation SSPipeline


- (void)disconnect
{
    [self.localSocket disconnectAfterReadingAndWriting];
    [self.remoteSocket disconnectAfterReadingAndWriting];
}

@end


@implementation ShadowsocksClient
{
    dispatch_queue_t _socketQueue;
    GCDAsyncSocket *_serverSocket;
    NSMutableArray *_pipelines;
    NSString *_host;
    NSInteger _port;
    NSString *_method;
    NSString *_passoword;
}

@synthesize host = _host;
@synthesize port = _port;
@synthesize method = _method;
@synthesize password = _passoword;





- (SSPipeline *)pipelineOfLocalSocket:(GCDAsyncSocket *)localSocket
{
    __block SSPipeline *ret;
    [_pipelines enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        SSPipeline *pipeline = obj;
        if (pipeline.localSocket == localSocket) {
            ret = pipeline;
        }
    }];
    return ret;
}

- (SSPipeline *)pipelineOfRemoteSocket:(GCDAsyncSocket *)remoteSocket
{
    __block SSPipeline *ret;
    [_pipelines enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        SSPipeline *pipeline = obj;
        if (pipeline.remoteSocket == remoteSocket) {
            ret = pipeline;
        }
    }];
    return ret;
}

- (void)dealloc
{
    _serverSocket = nil;
    _pipelines = nil;
    _host = nil;
}

- (void)updateHost:(NSString *)host port:(NSInteger)port password:(NSString *)passoword method:(NSString *)method
{
    _host = [host copy];
    _port = port;
    _passoword = [passoword copy];
    config_encryption([passoword cStringUsingEncoding:NSASCIIStringEncoding],
                      [method cStringUsingEncoding:NSASCIIStringEncoding]);
    _method = [method copy];
}

- (id)initWithHost:(NSString *)host port:(NSInteger)port password:(NSString *)passoword method:(NSString *)method
{
    self = [super init];
    if (self) {
#ifdef DEBUG
        NSLog(@"SS: %@", host);
#endif
        _host = [host copy];
        _port = port;
        _passoword = [passoword copy];
        config_encryption([passoword cStringUsingEncoding:NSASCIIStringEncoding],
                          [method cStringUsingEncoding:NSASCIIStringEncoding]);
        _method = [method copy];
    }
    return self;
}

- (BOOL)startWithLocalPort:(NSInteger)localPort
{
    if (_serverSocket) {
        [self stop];
        //        [NSThread sleepForTimeInterval:3];
        return [self _doStartWithLocalPort:localPort];
    } else {
        [self stop];
        return [self _doStartWithLocalPort:localPort];
    }
}

- (BOOL)_doStartWithLocalPort:(NSInteger)localPort
{
    _socketQueue = dispatch_queue_create("me.tuoxie.shadowsocks", NULL);
    _serverSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:_socketQueue];
    NSError *error;
    [_serverSocket acceptOnPort:localPort error:&error];
    if (error) {
        NSLog(@"bind failed, %@", error);
        return NO;
    }
    _pipelines = [[NSMutableArray alloc] init];
    return YES;
}

- (BOOL)isConnected
{
    return _serverSocket.isConnected;
}

- (void)stop
{
    [_serverSocket disconnect];
    NSArray *ps = [NSArray arrayWithArray:_pipelines];
    [ps enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        SSPipeline *pipeline = obj;
        [pipeline.localSocket disconnect];
        [pipeline.remoteSocket disconnect];
    }];
    _serverSocket = nil;
}
//这里处理的是本地socket的回调， 当有请求需要的时候会触发这个回调
- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
#ifdef DEBUG
    //    NSLog(@"didAcceptNewSocket");
#endif
    //实例化一个pipe
    SSPipeline *pipeline = [[SSPipeline alloc] init];
    //对pipe的localsocket赋值
    pipeline.localSocket = newSocket;
    //将pipe添加到数组中，将socket持有一下，不然会销毁。
    [_pipelines addObject:pipeline];
    //连接成功开始读数据
    //The tag is for your convenience. The tag you pass to the read operation is the tag that is passed back to you in the socket:didReadData:withTag: delegate callback.
    // 需要自己调用读取方法，socket才会调用代理方法读取数据
    //这个地方将tag置为0，接下来local socket拿到的数据就会是0，表明这是连接阶段
    [pipeline.localSocket readDataWithTimeout:-1 tag:0];
}
//这里处理的是remote socket的回调，当socket可读可写的时候调用
- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port
{
    /*
     {
     @public
     //发送的加密文
     struct encryption_ctx sendEncryptionContext;
     //接收的加密文
     struct encryption_ctx recvEncryptionContext;
     }
     //本地的socket，带来写出的数据
     @property (nonatomic, strong) GCDAsyncSocket *localSocket;
     //远端的socket，带来写入的数据
     @property (nonatomic, strong) GCDAsyncSocket *remoteSocket;
     //不知道是干嘛的
     @property (nonatomic, assign) int stage;
     //不知道是干嘛的
     @property (nonatomic, strong) NSData *addrData;
     */
    //SSPipeline 是一个socket代理两端双向通道的完整描述
    SSPipeline *pipeline = [self pipelineOfRemoteSocket:sock];
    //[pipeline.localSocket readDataWithTimeout:-1 tag:0];
    
    //NSLog(@"remote did connect to host");
    
    
    NSString *s = [[NSString alloc] initWithBytes:pipeline.addrData.bytes length:pipeline.addrData.length encoding:NSASCIIStringEncoding];
    
    NSLog(@"连接到host：%@后向remote发送%@数据", host,s);
    
    //向remotesocke写数据 并将tag切换为2， 会触发didWriteData
    //触发didWriteData中tag == 2的情况没有处理。
    //这里的pipe.addrData是请求的信息
    [pipeline.remoteSocket
     writeData:pipeline.addrData
     withTimeout:-1
     tag:2];
    
    
    
    // Fake reply
    //这个地方是告诉客户端应该以什么样的协议来通信（猜的）
    struct socks5_response response;
    response.ver = SOCKS_VERSION;
    response.rep = 0;
    response.rsv = 0;
    response.atyp = SOCKS_IPV4;
    
    struct in_addr sin_addr;
    inet_aton("0.0.0.0", &sin_addr);
    
    int reply_size = 4 + sizeof(struct in_addr) + sizeof(unsigned short);
    char *replayBytes = (char *)malloc(reply_size);
    
    memcpy(replayBytes, &response, 4);
    memcpy(replayBytes + 4, &sin_addr, sizeof(struct in_addr));
    *((unsigned short *)(replayBytes + 4 + sizeof(struct in_addr)))
    = (unsigned short) htons(atoi("22"));
    //向local socket写数据，也就是说向客户端发送一个自己构造的数据
    //触发didWriteData，并将tag切换为3
    [pipeline.localSocket
     writeData:[NSData dataWithBytes:replayBytes length:reply_size]
     withTimeout:-1
     tag:3];
    NSString *localData = [[NSString alloc] initWithBytes:replayBytes length:reply_size encoding:NSASCIIStringEncoding];
    
    NSLog(@"连接到host：%@后向local发送%@数据", host,localData);

    free(replayBytes);
}
//The tag parameter is the tag you passed when you requested the read operation. For example, in the readDataWithTimeout:tag: method.
//这里是核心方法，处理两个socket中的io数据，其中tag值由其他几个方法配合控制，以区分带过来的data是什么样的data，是应该加密给remote还是解密给local。
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    //    NSLog(@"socket did read data %d tag %ld", data.length, tag);
    


    SSPipeline *pipeline =
    [self pipelineOfLocalSocket:sock] ?: [self pipelineOfRemoteSocket:sock];
    if (!pipeline) {
        return;
    }
    int len = (int)data.length;
    if (tag == 0) {

        // write version + method
        //到这里，pipeline还只有local socket
        //localsocket发送数据，紧接着会调用didWrite方法
        [pipeline.localSocket
         writeData:[NSData dataWithBytes:"\x05\x00" length:2]
         withTimeout:-1
         tag:0];

    } else if (tag == 1) {
        //这个地方开始关联remote socket
        //这里拿到本地10800端口返回的数据
        //这个数据里面是请求的网址
        struct socks5_request *request = (struct socks5_request *)data.bytes;
        
        
        if (request->cmd != SOCKS_CMD_CONNECT) {
            NSLog(@"unsupported cmd: %d", request->cmd);
            struct socks5_response response;
            response.ver = SOCKS_VERSION;
            response.rep = SOCKS_CMD_NOT_SUPPORTED;
            response.rsv = 0;
            response.atyp = SOCKS_IPV4;
            char *send_buf = (char *)&response;
            [pipeline.localSocket writeData:[NSData dataWithBytes:send_buf length:4] withTimeout:-1 tag:1];
            [pipeline disconnect];
            return;
        }
        
        char addr_to_send[ADDR_STR_LEN];
        int addr_len = 0;
        addr_to_send[addr_len++] = request->atyp;
        
        char addr_str[ADDR_STR_LEN];
        // get remote addr and port
        if (request->atyp == SOCKS_IPV4) {
            // IP V4
            size_t in_addr_len = sizeof(struct in_addr);
            memcpy(addr_to_send + addr_len, data.bytes + 4, in_addr_len + 2);
            addr_len += in_addr_len + 2;
            
            // now get it back and print it
            inet_ntop(AF_INET, data.bytes + 4, addr_str, ADDR_STR_LEN);
        } else if (request->atyp == SOCKS_DOMAIN) {
            // Domain name
            unsigned char name_len = *(unsigned char *)(data.bytes + 4);
            addr_to_send[addr_len++] = name_len;
            memcpy(addr_to_send + addr_len, data.bytes + 4 + 1, name_len);
            memcpy(addr_str, data.bytes + 4 + 1, name_len);
            addr_str[name_len] = '\0';
            addr_len += name_len;
            
            // get port
            unsigned char v1 = *(unsigned char *)(data.bytes + 4 + 1 + name_len);
            unsigned char v2 = *(unsigned char *)(data.bytes + 4 + 1 + name_len + 1);
            addr_to_send[addr_len++] = v1;
            addr_to_send[addr_len++] = v2;
        } else {
            NSLog(@"unsupported addrtype: %d", request->atyp);
            [pipeline disconnect];
            return;
        }
        
        
        //实例化一个remote socket
        GCDAsyncSocket *remoteSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:_socketQueue];
        pipeline.remoteSocket = remoteSocket;
        //连接到远端主机；
        //在didConnected方法中会调用read方法，并将
        [remoteSocket connectToHost:_host onPort:_port error:nil];
        
        //初始化发送和接受加密数据的结构体
        init_encryption(&(pipeline->sendEncryptionContext));
        init_encryption(&(pipeline->recvEncryptionContext));
        //将地址信息加密,这个时候还没有发送出去，
        encrypt_buf(&(pipeline->sendEncryptionContext), addr_to_send, &addr_len);
        //正如之前提到过的，这里的addr_to_send就是请求
        pipeline.addrData = [NSData dataWithBytes:addr_to_send length:addr_len];
        
//        NSLog(@"%@++++", [[NSString alloc] initWithData:pipeline.addrData encoding:NSASCIIStringEncoding]);
        
    } else if (tag == 2) { // read data from local, send to remote
        //到这里都是发起请求的时候，参数里面带过来的一定是local socket写出的数据
        if (![_method isEqualToString:@"table"]) {
            
            
            char *buf = (char *)malloc(data.length + EVP_MAX_IV_LENGTH + EVP_MAX_BLOCK_LENGTH);
            memcpy(buf, data.bytes, data.length);
                        
            encrypt_buf(&(pipeline->sendEncryptionContext), buf, &len);
            NSData *encodedData = [NSData dataWithBytesNoCopy:buf length:len];
            //这里
            [pipeline.remoteSocket writeData:encodedData withTimeout:-1 tag:4];
        } else {
            encrypt_buf(&(pipeline->sendEncryptionContext), (char *)data.bytes, &len);
            [pipeline.remoteSocket writeData:data withTimeout:-1 tag:4];
        }
    } else if (tag == 3) { // read data from remote, send to local
        //到这里，一定是remote socket的回调，参数里面带过来的是remote socket写入的数据
        if (![_method isEqualToString:@"table"]) {
            char *buf = (char *)malloc(data.length + EVP_MAX_IV_LENGTH + EVP_MAX_BLOCK_LENGTH);
            memcpy(buf, data.bytes, data.length);
            
            //将收到的加密数据解密一下
            decrypt_buf(&(pipeline->recvEncryptionContext), buf, &len);
            //将解密后的数据包装成NSData
            NSData *encodedData = [NSData dataWithBytesNoCopy:buf length:len];
            //向10800端口写解密后的数据，现在tag是3，在didWrite的回调中切换tag
            [pipeline.localSocket writeData:encodedData withTimeout:-1 tag:3];
        } else {
            decrypt_buf(&(pipeline->recvEncryptionContext), (char *)data.bytes, &len);
            [pipeline.localSocket writeData:data withTimeout:-1 tag:3];
        }
    }
}

//socket写出完成的时候会调用
- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
    //    NSLog(@"socket did write tag %ld", tag);
    
    SSPipeline *pipeline =
    [self pipelineOfLocalSocket:sock] ?: [self pipelineOfRemoteSocket:sock];
    
    if (tag == 0) {
        //从local socket发出去的建立连接的数据已经送出，这时将tag切换为1，此时也只有local socket
        //接下来触发的就是didReadData,对应的就是开始连接remote socket
        [pipeline.localSocket readDataWithTimeout:-1 tag:1];
    } else if (tag == 1) {
        
    } else if (tag == 2) {
        
    } else if (tag == 3) { // write data to local
        //从remote socket中读取消息，将tag置为3,在didRead中回调
        //从local socket中读取消息，将tag置为2，在didRead中回调
        [pipeline.remoteSocket readDataWithTimeout:-1 buffer:nil bufferOffset:0 maxLength:4096 tag:3];
        [pipeline.localSocket readDataWithTimeout:-1 buffer:nil bufferOffset:0 maxLength:4096 tag:2];
    } else if (tag == 4) { // write data to remote
        //从remote socket中读取消息，将tag置为3,在didRead中回调
        //从local socket中读取消息，将tag置为2，在didRead中回调
        [pipeline.remoteSocket readDataWithTimeout:-1 buffer:nil bufferOffset:0 maxLength:4096 tag:3];
        [pipeline.localSocket readDataWithTimeout:-1 buffer:nil bufferOffset:0 maxLength:4096 tag:2];
    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
    SSPipeline *pipeline;
    
    pipeline = [self pipelineOfRemoteSocket:sock];
    if (pipeline) { // disconnect remote
        if (pipeline.localSocket.isDisconnected) {
            [_pipelines removeObject:pipeline];
            // encrypt code
            cleanup_encryption(&(pipeline->sendEncryptionContext));
            cleanup_encryption(&(pipeline->recvEncryptionContext));
        } else {
            [pipeline.localSocket disconnectAfterReadingAndWriting];
        }
        return;
    }
    
    pipeline = [self pipelineOfLocalSocket:sock];
    if (pipeline) { // disconnect local
        if (pipeline.remoteSocket.isDisconnected) {
            [_pipelines removeObject:pipeline];
            // encrypt code
            cleanup_encryption(&(pipeline->sendEncryptionContext));
            cleanup_encryption(&(pipeline->recvEncryptionContext));
        } else {
            [pipeline.remoteSocket disconnectAfterReadingAndWriting];
        }
        return;
    }
}

@end

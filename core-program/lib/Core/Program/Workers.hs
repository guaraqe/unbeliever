{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StrictData #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# OPTIONS_HADDOCK prune #-}

{- |
Utility functions for building programs which consume work off of a queue.
-}
module Core.Program.Workers
    ( -- * Concurrency
      runWorkers_
    , mapWorkers

      -- * Internals
    ) where

import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TQueue (TQueue, flushTQueue, newTQueueIO, readTQueue, unGetTQueue, writeTQueue)
import Control.Monad
    ( forM
    )
import Core.Program.Context
import Core.Program.Threads
import Core.System.Base

{-
-- or perhaps Foldable?
runConcurrentThreads :: Traversable ω => Int -> (α -> Program τ β) -> ω α -> Program τ (ω β)
runConcurrentThreads :: Limit -> (α -> Program τ β) -> [α] -> Program τ [β]
-}

{- |
Run a pool of worker threads which consume items off a queue.

You create the work queue of items by initializing a queue of 'Maybe' @α@ with
this:

@
import "Control.Concurrent.STM.TQueue" (TQueue, newTQueueIO)
@

and

@
    queue :: 'TQueue' ('Maybe' Thing) <- 'liftIO' $ do
        'newTQueueIO'

    runWorkers_ 16 worker queue
@

If this was a queue of @α@s then it would never return. Instead it's a queue
of 'Maybe' @α@s so that you can signal end-of-work by writing a 'Nothing' down
the pipeline when you're finished generating input.

It is assumed that the workers have a way of communicating their results
onwards (either because they are side-effecting in the real world themselves,
or because you have passed in some queue to collect the results, for example).

@since 0.6.9
-}
runWorkers_ :: Int -> (α -> Program τ ()) -> TQueue (Maybe α) -> Program τ ()
runWorkers_ n action queue = do
    createScope $ do
        ts <- forM [1 .. n] $ \_ -> do
            forkThread $ do
                loop
        _ <- waitThreads' ts
        pure ()
  where
    loop = do
        possibleItem <- liftIO $ do
            atomically $ do
                readTQueue queue -- blocks
        case possibleItem of
            Nothing -> do
                --
                -- We put the Nothing back so that other workers can also shutdown.
                --
                liftIO $ do
                    atomically $ do
                        unGetTQueue queue Nothing
            Just item -> do
                --
                -- Do the work
                --
                action item
                loop

{- |
Map a pool of workers over a list concurrently.

Simply forking one Haskell thread for every item in a list is a suprisingly
reasonable choice in many circumstances given how good Haskell's concurrency
machinery is, and in this library can be achieved by 'Control.Monad.forM'ing
'forkThread' over a list of items. But if you need tighter control over the
amount of concurrency—as is often the case when doing something
computationally heavy or making requests of an external service with known
limitations—then you are better off using this function.

(this was originally modelled on __async__\'s
'Control.Concurrent.Async.mapConcurrently'. That function has the drawback
that the number of threads created is set by the size of the structure being
traversed)

@since 0.6.9
-}
mapWorkers :: Int -> (α -> Program τ β) -> [α] -> Program τ [β]
mapWorkers n action list = do
    inputs <- liftIO $ do
        newTQueueIO :: IO (TQueue (Maybe α))

    outputs <- liftIO $ do
        newTQueueIO :: IO (TQueue β)

    --
    -- Load the input list into a queue followed by a terminator.
    --

    liftIO $ do
        atomically $ do
            mapM_
                ( \item ->
                    writeTQueue inputs (Just item)
                )
                list
            writeTQueue inputs Nothing

    --
    -- Invoke the general concurrent workers tool above to process the queue.
    --

    runWorkers_
        n
        ( \item -> do
            result <- action item
            liftIO $ do
                atomically $ do
                    writeTQueue outputs result
        )
        inputs

    --
    -- Convert the results back to a list.

    liftIO $ do
        atomically $ do
            flushTQueue outputs
